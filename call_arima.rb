#!/usr/bin/env ruby
# call_arima.rb
require 'net/http'
require 'uri'
require 'json'
require 'csv'
require 'fileutils'

SERVICE_URL = ENV['ARIMA_URL'] || "http://127.0.0.1:8000/arima"
CSV_PATH = ENV['DATA_PATH'] || File.join(Dir.home, "Desktop", "Ruby", "forecast_project", "stores_sales_forecasting.pandas.csv")
OUT_DIR = ENV['OUT_DIR'] || "output"
FileUtils.mkdir_p(OUT_DIR)

# Request payload
payload = {
  csv_path: CSV_PATH,
  date_col: ENV['DATE_COL'] || "Order Date",
  sales_col: ENV['SALES_COL'] || "Sales",
  periods: (ENV['PERIODS'] || 30).to_i,
  freq: ENV['FREQ'] || "D",
  order: nil, # e.g. [1,1,1] or nil for default
  seasonal_order: nil
}

uri = URI.parse(SERVICE_URL)
req = Net::HTTP::Post.new(uri.request_uri, {'Content-Type' => 'application/json'})
req.body = payload.to_json

puts "POSTing to #{SERVICE_URL} with payload: #{payload}"
res = Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(req) }

unless res.is_a?(Net::HTTPSuccess)
  puts "Service returned non-success: #{res.code} #{res.body}"
  exit 1
end

result = JSON.parse(res.body)
if result['error']
  puts "Service error: #{result['error']}"
  exit 1
end

forecast = result['forecast']  # array of {date, mean, lower_ci, upper_ci}
history = result['history_tail']

# Save forecast CSV
CSV.open(File.join(OUT_DIR, "arima_forecast.csv"), "w") do |csv|
  csv << ['date', 'predicted', 'lower_ci', 'upper_ci']
  forecast.each do |r|
    csv << [r['date'], r['mean'], r['lower_ci'], r['upper_ci']]
  end
end

# Optionally print history tail
puts "History tail (last few observations):"
history.each { |h| puts "#{h['date']}: #{h['value']}" }

puts "Arima forecast saved to #{OUT_DIR}/arima_forecast.csv"
