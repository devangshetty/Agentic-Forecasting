#!/usr/bin/env ruby
# call_arima.rb
# POST to FastAPI ARIMA service and insert returned forecast into DB (table 'forecasts').

require 'net/http'
require 'uri'
require 'json'
require 'csv'
require 'fileutils'
require 'sequel'
require 'date'

OUT_DIR = ENV['OUT_DIR'] || "output"
FileUtils.mkdir_p(OUT_DIR)

SERVICE_URL = ENV['ARIMA_URL'] || "http://127.0.0.1:8000/arima"
CSV_PATH = ENV['DATA_PATH'] || File.join(Dir.home, "Desktop", "Ruby", "forecast_project", "stores_sales_forecasting.pandas.csv")

DB_URL = ENV['DATABASE_URL'] || "postgres://#{ENV['POSTGRES_USER'] || 'postgres'}:#{ENV['POSTGRES_PASSWORD'] || 'postgres_password'}@#{ENV['DB_HOST'] || 'db'}:5432/#{ENV['POSTGRES_DB'] || 'forecast_db'}"
DB = Sequel.connect(DB_URL) rescue nil

payload = {
  csv_path: CSV_PATH,
  date_col: ENV['DATE_COL'] || "Order Date",
  sales_col: ENV['SALES_COL'] || "Sales",
  periods: (ENV['PERIODS'] || 30).to_i,
  freq: ENV['FREQ'] || "D",
  order: nil,
  seasonal_order: nil,
  use_db: (ENV['USE_DB'] == '1' ? true : false)
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

forecast = result['forecast'] || []
history = result['history_tail'] || []

# Save CSV for convenience
CSV.open(File.join(OUT_DIR, "arima_forecast.csv"), "w") do |csv|
  csv << ['date','predicted','lower_ci','upper_ci']
  forecast.each do |r|
    csv << [r['date'], r['mean'], r['lower_ci'], r['upper_ci']]
  end
end
puts "Arima forecast saved to #{OUT_DIR}/arima_forecast.csv"

# Insert into DB if available
if DB
  DB.transaction do
    forecast.each do |r|
      begin
        DB[:forecasts].insert(
          forecast_date: Date.parse(r['date']),
          model: 'arima',
          predicted: r['mean'].to_f,
          lower_ci: (r['lower_ci'] ? r['lower_ci'].to_f : nil),
          upper_ci: (r['upper_ci'] ? r['upper_ci'].to_f : nil)
        )
      rescue => e
        warn "Insert failed for #{r['date']}: #{e}"
      end
    end
  end
  puts "Inserted #{forecast.length} ARIMA rows into forecasts table"
else
  puts "DATABASE not configured; skipping DB insert. Set DATABASE_URL or USE_DB env to enable."
end
