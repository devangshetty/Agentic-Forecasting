#!/usr/bin/env ruby
# forecast_agent.rb
require 'net/http'
require 'uri'
require 'json'
require 'open3'
require 'fileutils'

FORECAST_SCRIPT = "./forecast.rb"
OPENAI_KEY = ENV['OPENAI_API_KEY'] || nil
ALLOWED_ACTIONS = %w[train eval set_param increase_trees decrease_trees save stop]
MODEL_NAME = ENV['LLM_MODEL'] || "gpt-4o-mini"
LOG_PATH = "output/agent_log.txt"
FileUtils.mkdir_p("output")

def log(msg)
  ts = Time.now.utc.iso8601
  File.open(LOG_PATH, "a") { |f| f.puts "#{ts}  #{msg}" }
  puts msg
end

def call_openai_system(prompt)
  raise "OPENAI_API_KEY not set. Set env var OPENAI_API_KEY to use the agent." unless OPENAI_KEY
  uri = URI.parse("https://api.openai.com/v1/chat/completions")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  body = {
    model: MODEL_NAME,
    messages: [
      { role: "system", content: "You are an experiment orchestration assistant. Only respond with valid JSON describing one action from the allowed list: #{ALLOWED_ACTIONS.join(', ')}. Example: {\"action\":\"train\",\"params\":{}}. Do not include any extra text."},
      { role: "user", content: prompt }
    ],
    max_tokens: 300,
    temperature: 0.0
  }.to_json

  req = Net::HTTP::Post.new(uri.request_uri,
    'Content-Type' => 'application/json',
    'Authorization' => "Bearer #{OPENAI_KEY}"
  )
  req.body = body
  res = http.request(req)
  raise "OpenAI error: #{res.code} #{res.body}" unless res.is_a?(Net::HTTPSuccess)
  parsed = JSON.parse(res.body)
  parsed["choices"][0]["message"]["content"]
end

def safe_parse_json(s); JSON.parse(s) rescue nil; end

def run_forecast_with_env(env = {})
  cmd_env = env.map { |k,v| "#{k}=#{v}" }.join(" ")
  cmd = "#{cmd_env} bundle exec ruby #{FORECAST_SCRIPT}"
  log("EXEC -> #{cmd}")
  stdout, stderr, status = Open3.capture3(cmd)
  log("STDOUT: #{stdout}")
  log("STDERR: #{stderr}") unless stderr.strip.empty?
  status.success?
end

state = { "n_estimators" => (ENV['MODEL_N_ESTIMATORS']||200).to_i,
          "max_depth" => (ENV['MODEL_MAX_DEPTH']||8).to_i,
          "lags" => (ENV['LAGS']||14).to_i,
          "train_frac" => (ENV['TRAIN_FRAC']||0.8).to_f }

loop_count = 0
loop do
  loop_count += 1
  prompt = "Current experiment state: #{state.to_json}. Options: train -> run training; eval -> run training+report metrics; set_param -> set a state param; increase_trees -> increase n_estimators by 50; decrease_trees -> decrease by 50; save -> save artifacts; stop -> stop. Respond with a JSON object {\"action\":\"...\",\"params\":{...}}. Make a single decision for the next step."
  log("Asking LLM for action (loop #{loop_count})")
  raw = call_openai_system(prompt)
  log("LLM raw: #{raw}")
  obj = safe_parse_json(raw)
  if obj.nil?
    log("LLM did not return valid JSON. Stopping.")
    break
  end
  action = obj["action"]
  params = obj["params"] || {}

  unless ALLOWED_ACTIONS.include?(action)
    log("Disallowed action: #{action}. Stopping.")
    break
  end

  case action
  when "train", "eval"
    env = { "LAGS" => state["lags"], "TRAIN_FRAC" => state["train_frac"], "MODEL_N_ESTIMATORS" => state["n_estimators"], "MODEL_MAX_DEPTH" => state["max_depth"] }
    success = run_forecast_with_env(env)
    log("Train/Eval success: #{success}")
  when "set_param"
    params.each { |k,v| state[k.to_s] = v if state.key?(k.to_s) }
    log("State updated: #{state}")
  when "increase_trees"
    state["n_estimators"] = (state["n_estimators"] || 200) + 50
    log("Increased trees -> #{state['n_estimators']}")
  when "decrease_trees"
    state["n_estimators"] = [(state["n_estimators"] || 200) - 50, 10].max
    log("Decreased trees -> #{state['n_estimators']}")
  when "save"
    log("Save action: forecast and metrics already saved by forecast.rb")
  when "stop"
    log("Agent requested stop. Exiting.")
    break
  end

  break if loop_count >= 6
  sleep 0.5
end

log("Agent loop finished.")
