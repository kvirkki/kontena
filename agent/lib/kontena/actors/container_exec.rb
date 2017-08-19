require_relative '../helpers/rpc_helper'

module Kontena::Actors
  class ContainerExec
    include Celluloid
    include Kontena::Logging
    include Kontena::Helpers::RpcHelper

    exclusive :input

    attr_reader :uuid

    # @param [Docker::Container] container
    def initialize(container)
      @uuid = SecureRandom.uuid
      @container = container
      @read_pipe, @write_pipe = IO.pipe
      info "initialized (session #{@uuid})"
    end

    # @param [String] input
    def input(input)
      if input.nil?
        @write_pipe.close
      else
        @write_pipe.write(input)
      end
    end

    # @param [Hash] size
    # @option size [Integer] width
    # @option size [Integer] height
    def tty_resize(size)
      return unless @container_exec

      begin
        @container_exec.resize({
          'w' => size['width'], 'h' => size['height']
        })
      rescue Docker::Error::NotFoundError
        sleep 0.1
        retry if @container_exec
      end
    end

    # @param [String] cmd
    # @param [Boolean] tty
    # @param [Boolean] stdin
    def run(cmd, tty = false, stdin = false)
      info "starting command: #{cmd} (tty: #{tty}, stdin: #{stdin})"
      exit_code = 0
      @container_exec = build_exec(cmd, tty: tty, stdin: stdin)
      defer {
        start_opts = {
          tty: tty,
          stdin: @read_pipe,
          detach: false
        }
        if tty
          _, _, exit_code = start_exec(start_opts) do |chunk|
            self.handle_stream_chunk('stdout'.freeze, chunk)
          end
        else
          _, _, exit_code = start_exec(start_opts) do |stream, chunk|
            self.handle_stream_chunk(stream, chunk)
          end
        end
      }
    ensure
      info "command finished: #{cmd} with code #{exit_code}"
      shutdown(exit_code)
    end

    # @param [Array<String>] command
    # @param [Boolean] stdin
    # @param [Boolean] tty
    # @return [Docker::Exec]
    def build_exec(command, stdin: false, tty: false)
      opts = {
        'Container' => @container.id,
        'AttachStdin' => stdin,
        'AttachStdout' => true,
        'AttachStderr' => true,
        'Tty' => tty,
        'Cmd' => command
      }
      opts['Env'] = ['TERM=xterm'] if tty && stdin

      # Create Exec Instance
      Docker::Exec.create(
        opts,
        @container.connection
      )
    end

    # @param [Hash] options
    # @option options [Boolean] tty
    # @option options [IO] stdin
    # @option options [Boolean] detach
    def start_exec(options, &block)
      @container_exec.start!(options, &block)
    end

    # @param [String] stream
    # @param [String] chunk
    def handle_stream_chunk(stream, chunk)
      rpc_client.notification('/container_exec/output', [@uuid, stream, chunk.force_encoding(Encoding::UTF_8)])
    end

    # @param [Integer] exit_code
    def shutdown(exit_code)
      rpc_client.notification('/container_exec/exit', [@uuid, exit_code])
      self.terminate
    end
  end
end
