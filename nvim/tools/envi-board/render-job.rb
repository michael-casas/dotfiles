# frozen_string_literal: true
# Trusted host-only entrypoint. No document filename, Ruby option or plugin is
# accepted. stdin is Mermaid text. Seatbelt constrains reads/network/children.
Process.setrlimit(:CPU, 4, 4)
# macOS rejects RLIMIT_DATA/AS; parent enforces sampled resident-memory ceiling.
Process.setrlimit(:FSIZE, 0, 0)
Process.setrlimit(:NOFILE, 64, 64)
require 'json'
require_relative 'vendor/merminal-0.1.0/lib/merminal'
abort 'Ruby >= 3.3 required' if (RUBY_VERSION.split('.').map(&:to_i)[0, 2] <=> [3, 3]) == -1
abort 'renderer pin mismatch' unless Merminal::VERSION == '0.1.0'
input = $stdin.read(50 * 1024 + 1)
abort 'input limit' if input.bytesize > 50 * 1024
begin
  document = Merminal.parse(input, strict: true)
  abort 'renderer diagnostics; partial output discarded' unless document.diagnostics.empty?
  output = document.render(color: false, fit: nil)
  abort 'output limit' if output.bytesize > 16 * 1024 * 1024
  $stdout.write(output)
rescue StandardError
  abort 'renderer rejected diagram'
end
