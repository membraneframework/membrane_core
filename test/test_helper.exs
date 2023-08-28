# needed for testing distribution features
System.cmd("epmd", ["-daemon"])
Node.start(:"my_node@127.0.0.1", :longnames)

ExUnit.configure(formatters: [ExUnit.CLIFormatter, JUnitFormatter])
# ExUnit.start(exclude: [:long_running], assert_receive_timeout: 500)
ExUnit.start(exclude: [:long_running], capture_log: true, assert_receive_timeout: 500)
