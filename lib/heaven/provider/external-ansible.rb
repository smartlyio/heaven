module Heaven
  # Top-level module for providers.
  module Provider
    # The capistrano provider.
    class ExternalAnsible < DefaultProvider
      def initialize(guid, payload)
        super
        @name = "external-ansible"
        @guid = guid
      end

      def ansible_repo_name
        data["deployment"]["payload"]["config"]["ansible"]
      end

      def project_to_deploy
        data["deployment"]["payload"]["config"]["project"]
      end

      def deploy_target
        data["deployment"]["payload"]["config"]["target"] || "all"
      end

      def deploy_version
        data["deployment"]["ref"]
      end

      def ansible_root
        @ansible_root ||= "/tmp/" + \
          Digest::SHA1.hexdigest([ansible_repo_name, github_token].join)
      end

      def octokit_web_endpoint
        ENV["OCTOKIT_WEB_ENDPOINT"] || "https://github.com/"
      end

      def ansible_repository_url
        octokit_web_endpoint + ansible_repo_name
      end

      def ansible_clone_url
        uri = Addressable::URI.parse(ansible_repository_url)
        uri.user = github_token
        uri.password = ""
        uri.to_s
      end

      def ansible_branch
        data["deployment"]["payload"]["config"]["ansible_branch"] || "master"
      end


      def execute
        return execute_and_log(["/usr/bin/true"]) if Rails.env.test?

        log "This is external Ansible deployment provider!"

        unless File.exist?(ansible_root)
          log "Cloning #{ansible_clone_url} into #{ansible_root}"
          execute_and_log(["git", "clone", ansible_clone_url, ansible_root])
        end

        if project_to_deploy == "app"
          img_data = data.clone
          phpworkers_data = data.clone
          img_data["deployment"]["payload"]["config"]["project"] = "img"
          phpworkers_data["deployment"]["payload"]["config"]["project"] = "phpworkers"
          Resque.enqueue(Heaven::Jobs::Deployment, "#{@guid}-img", img_data)
          Resque.enqueue(Heaven::Jobs::Deployment, "#{@guid}-phpworkers", phpworkers_data)
        end

        Dir.chdir(ansible_root) do
          execute_and_log(["git", "fetch"])
          execute_and_log(["git", "reset", "--hard", ansible_branch])
          execute_and_log(["git-crypt", "unlock", "/usr/lib/heaven/crypt-key"])
          execute_and_log(["find . -name deploy_key.priv -exec chmod 0600 {} \\;"])

          ansible_hosts_file = "#{ansible_root}/servers"
          ansible_site_file = "#{ansible_root}/ansistrano_deploy_#{project_to_deploy}.yml"

          unless File.file?(ansible_site_file)
            log "ERROR_INVALID_PROJECT"
            exit 101
          end

          ansible_extra_vars = [
            "heaven_deploy_sha=#{sha}",
            "ansible_ssh_private_key_file=/usr/lib/heaven/id_rsa",
            "ansible_ssh_common_args='-o ControlMaster=auto -o ControlPersist=600s'",
            "pipelining=True",
            "version=#{deploy_version}",
            "ansistrano_release_version=#{deploy_version}-#{Time.now.strftime('%Y%m%d%H%M%SZ')}",
          ].map { |e| "-e #{e}" }.join(" ")

          deploy_string = ["ansible-playbook", "-i", ansible_hosts_file, "-l", deploy_target, ansible_site_file,
                           "--verbose", "#{ansible_extra_vars}",
                            "-u", "smartly", "-vvvv"]
          execute_and_log(deploy_string,  "ANSIBLE_HOST_KEY_CHECKING" => "false")
        end
      end
    end
  end
end
