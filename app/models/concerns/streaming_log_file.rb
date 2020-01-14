# A module to include for easy access to writing to a transient filesystem
module StreamingLogFile
  extend ActiveSupport::Concern
  include DeploymentTimeout

  def working_directory
    @working_directory ||= "/tmp/" + \
      Digest::SHA1.hexdigest([name_with_owner, github_token].join)
  end

  def checkout_directory
    "#{working_directory}/checkout"
  end

  def stdout_file
    "#{working_directory}/stdout.#{guid}.log"
  end

  def stderr_file
    "#{working_directory}/stderr.#{guid}.log"
  end

  def stdout_file_fd
    @stdout_fd = File.open(stdout_file, "a") if !@stdout_fd || @stdout_fd.closed?
    @stdout_fd
  end

  def stderr_file_fd
    @stderr_fd = File.open(stderr_file, "a") if !@stderr_fd || @stderr_fd.closed?
    @stderr_fd
  end

  def read_and_log(stdout, stderr, timeout = nil)
    readers = [stdout, stderr]
    start = Time.now

    while readers.any?
      ready = IO.select(readers, [], readers, timeout)
      raise POSIX::Spawn::TimeoutExceeded if ready.nil?

      ready[0].each do |fd|
        begin
          line = fd.readline.force_encoding("utf-8")
          if fd == stdout
            stdout_file_fd.write(line)
            Rails.logger.info(line.chomp)
          else
            stderr_file_fd.write(line)
            Rails.logger.error(line.chomp)
          end
        rescue Errno::EAGAIN, Errno::EINTR
        rescue EOFError
          readers.delete(fd)
          fd.close
        end
      end

      @runtime = Time.now - start
      raise POSIX::Spawn::TimeoutExceeded if timeout && timeout - @runtime  < 0.0
    end
  end


  def execute_and_log(cmds, env = {})
    # Don't add single/double quotes around to any cmd in cmds.
    # For example,
    #   cmds = ["my_command", "'foo=bar lazy=true'"] will fail
    # The correct way is
    #   cmds = ["my_command", "foo=bar lazy=true"]
    Rails.logger.info "Executing cmds: #{cmds}"
    pid, stdin, stdout, stderr = POSIX::Spawn::popen4(env, *cmds)
    read_and_log(stdout, stderr, execute_options[:timeout])

    ::Process::waitpid(pid)
    @last_child = $?
    unless @last_child.success?
      fail StandardError, "Task failed: #{cmds.join(" ")}"
    end
    @last_child
  rescue => e
    if stderr_file_fd && !stderr_file_fd.closed?
      stderr_file_fd.write(e.backtrace.join("\n") + "\n")
      stderr_file_fd.write(e.to_s + "\n")
    end
    if @last_child.nil? && pid
      ::Process::kill('TERM', pid) rescue nil
      ::Process::waitpid(pid)
      @last_child = $?
    end
    raise
  ensure
    [stdin, stdout, stderr, stdout_file_fd, stderr_file_fd].each { |fd| fd.close rescue nil }
  end

  def execute_options
    if terminate_child_process_on_timeout
      { :timeout => deployment_time_remaining - 2 }
    else
      {}
    end
  end

  def terminate_child_process_on_timeout
    ENV["TERMINATE_CHILD_PROCESS_ON_TIMEOUT"] == "1"
  end
end
