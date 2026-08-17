#!/usr/bin/env ruby
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

require "yaml"

workflow_path = ARGV.fetch(0, ".github/workflows/ci.yml")

def require_contract(condition, message)
  abort("CI contract error: #{message}") unless condition
end

workflow = YAML.safe_load(File.read(workflow_path), aliases: false)
require_contract(workflow.is_a?(Hash), "the workflow must be a YAML mapping")
require_contract(workflow["permissions"] == { "contents" => "read" }, "permissions must be read-only")

concurrency = workflow["concurrency"]
require_contract(concurrency.is_a?(Hash), "concurrency must be configured")
require_contract(concurrency["cancel-in-progress"] == true, "superseded runs must be cancelled")

job = workflow.dig("jobs", "verify")
require_contract(job.is_a?(Hash), "the verify job is missing")
require_contract(job["runs-on"] == "macos-15", "the verify job must use the macos-15 Arm64 image")
require_contract(job.dig("env", "DEVELOPER_DIR") == "/Applications/Xcode_26.3.app/Contents/Developer", "Xcode 26.3 must be selected")

steps = job["steps"]
require_contract(steps.is_a?(Array), "the verify job must have steps")
checkout = steps.find { |step| step["uses"]&.start_with?("actions/checkout@") }
require_contract(checkout, "actions/checkout is missing")
checkout_reference = checkout.fetch("uses").split("@", 2).last
require_contract(checkout_reference.match?(/\A[0-9a-f]{40}\z/), "actions/checkout must use a full commit SHA")
require_contract(checkout.dig("with", "persist-credentials") == false, "checkout credentials must not persist")

run_commands = steps.map { |step| step["run"] }.compact.join("\n")
[
  "scripts/ci/install-xcodegen.sh",
  "scripts/ci/verify.sh",
].each do |required_command|
  require_contract(run_commands.include?(required_command), "#{required_command} is not executed")
end

serialized = File.read(workflow_path)
require_contract(!serialized.include?("secrets."), "the workflow must not use secrets")
require_contract(!serialized.include?("upload-artifact"), "the workflow must not upload artifacts")
require_contract(!serialized.match?(/codesign|notar/i), "the workflow must not sign or notarize")

puts "CI workflow contract is valid."
