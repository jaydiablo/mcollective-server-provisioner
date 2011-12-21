require "yaml"

module MCollective
    module Agent
        class Provision<RPC::Agent
            metadata :name => "Server Provisioning Agent",
                     :description => "Agent to assist in provisioning new servers",
                     :author => "R.I.Pienaar",
                     :license => "Apache 2.0",
                     :version => "2.0",
                     :url => "http://www.devco.net/",
                     :timeout => 360


            def startup_hook
                config = Config.instance

                certname = PluginManager["facts_plugin"].get_fact("fqdn")
                certname = config.identity unless certname

                @puppetcert = config.pluginconf["provision.certfile"] || "/var/lib/puppet/ssl/certs/#{certname}.pem"
                @lockfile = config.pluginconf["provision.lockfile"] || "/tmp/mcollective_provisioner_lock"
                @puppetd = config.pluginconf["provision.puppetd"] || "/usr/sbin/puppetd"
                @fact_add = config.pluginconf["provision.fact_add"] || "/usr/bin/fact-add"
                @fact_yaml = config.pluginconf["provision.fact_yaml"] || "/etc/mcollective/facts.yaml"
            end

            action "set_puppet_host" do
                validate :ipaddress, :ipv4address

                begin
                    hosts = File.readlines("/etc/hosts")

                    File.open("/etc/hosts", "w") do |hosts_file|
                        hosts.each do |host|
                            hosts_file.puts host unless host =~ /puppet/
                        end

                        hosts_file.puts "#{request[:ipaddress]}\tpuppet"
                    end
                rescue Exception => e
                    fail "Could not add hosts entry: #{e}"
                end
            end

            # does a run of puppet with --tags no_such_tag_here
            action "request_certificate" do
                reply[:output] = %x[#{@puppetd} --test --tags no_such_tag_here --color=none --summarize]
                reply[:exitcode] = $?.exitstatus

                # dont fail here if exitcode isnt 0, it'll always be non zero
            end

            # does a run of puppet with --environment bootstrap or similar
            action "bootstrap_puppet" do
                reply[:output] = %x[#{@puppetd} --test --environment bootstrap --color=none --summarize]
                reply[:exitcode] = $?.exitstatus

                fail "Puppet returned #{reply[:exitcode]}" if reply[:exitcode] == 1
            end

            # does a normal puppet run
            action "run_puppet" do
                reply[:output] = %x[#{@puppetd}]
                reply[:exitcode] = $?.exitstatus

                fail "Puppet returned #{reply[:exitcode]}" if reply[:exitcode] == 1
            end

            action "has_cert" do
                reply[:has_cert] = has_cert?
            end

            action "fact_mod" do
                validate :fact, :value

                # Store in fact.yaml as well
                facts = YAML::load(File.open(@fact_yaml))
                if !facts.is_a?(Hash)
                    facts = Hash.new
                end
                facts[request[:fact]] = request[:value]
                # Write facts to yaml file
                File.open(@fact_yaml, "w") do |f|
                    f.write(facts.to_yaml)
                end
                
                reply[:output] = %x[#{@fact_add} #{request[:fact]} #{request[:value]}]
		        reply[:exitcode] = $?.exitstatus

                if reply[:exitcode] != 0
                    File.unlink(@lockfile)
                    fail "Fact returned #{reply[:exitcode]}"
                end
            end

            action "lock_deploy" do
                reply.fail! "Already locked" if locked?

                File.open(@lockfile, "w") {|f| f.puts Time.now}

                reply[:lockfile] = @lockfile

                reply.fail! "Failed to lock the install" unless locked?
            end

            action "is_locked" do
                reply[:locked] = locked?
            end

            action "unlock_deploy" do
                File.unlink(@lockfile)
                reply[:unlocked] = locked?
                reply.fail! "Failed to unlock the install" if locked?
            end

            private
            def has_cert?
                File.exist?(@puppetcert)
            end

            def locked?
                File.exist?(@lockfile)
            end
        end
    end
end
