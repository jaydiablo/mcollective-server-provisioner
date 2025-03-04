module MCProvision::Util
    # Parses a -W style filter and return a std filter option
    def self.parse_filter(agent, filter)
        result = MCollective::Util.empty_filter

        filter.split(" ").each do |f|
            if f =~ /^(.+?)=(.+)/
                if MCollective::Util.method(:has_fact?).arity == 2
                    result["fact"] << {:fact => $1, :value => $2}
                else
                    result["fact"] << {:fact => $1, :value => $2, :operator => "=="}
                end
            else
                result["cf_class"] << f
            end
        end

        result["agent"] << agent

        result
    end

    # Daemonize the current process
    def self.daemonize
        fork do
            Process.setsid
            exit if fork
            Dir.chdir('/tmp')
            STDIN.reopen('/dev/null')
            STDOUT.reopen('/dev/null', 'a')
            STDERR.reopen('/dev/null', 'a')

            if File.directory?("/var/run")
                File.open("/var/run/mcprovision.pid", 'w') {|f| f.write(Process.pid) } rescue true
            end

            yield
        end
    end

    def self.log(msg)
        MCProvision.debug(msg)
    end
end
