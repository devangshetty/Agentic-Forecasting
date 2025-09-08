#!/usr/bin/env ruby
# forecast.rb
# Robust Ruby forecasting script (Daru + Rumale + Numo)
# - handles common encoding/newline CSV issues (attempts cleaning if CSV read fails)
# - builds lag features, trains RandomForest (Rumale), evaluates, and writes outputs
#
# Environment vars (optional):
#   DATA_PATH (default: /Users/devangshetty/Desktop/Ruby/forecast_project/stores_sales_forecasting.csv)
#   DATE_COL  (default: "Order Date")
#   SALES_COL (default: "Sales")
#   LAGS      (default: 14)
#   TRAIN_FRAC (default: 0.8)
#   MODEL_N_ESTIMATORS (default: 200)
#   MODEL_MAX_DEPTH    (default: 8)
#   OUT_DIR   (default: "output")

require 'daru'
require 'rumale'
require 'csv'
require 'date'
require 'fileutils'
require 'json'
require 'numo/narray'

# <-- EDIT: default path set to your Desktop/Ruby project folder
DEFAULT_DATA_PATH = File.join(Dir.home, "Desktop", "Ruby", "forecast_project", "stores_sales_forecasting.csv")

DATA_PATH = ENV['DATA_PATH'] || DEFAULT_DATA_PATH
DATE_COL = ENV['DATE_COL'] || "Order Date"
SALES_COL = ENV['SALES_COL'] || "Sales"
LAGS = (ENV['LAGS'] || 14).to_i
TRAIN_FRAC = (ENV['TRAIN_FRAC'] || 0.8).to_f
MODEL_N_ESTIMATORS = (ENV['MODEL_N_ESTIMATORS'] || 200).to_i
MODEL_MAX_DEPTH = (ENV['MODEL_MAX_DEPTH'] || 8).to_i
OUT_DIR = ENV['OUT_DIR'] || "output"

FileUtils.mkdir_p(OUT_DIR)

def ensure_utf8_csv(path)
  unless File.exist?(path)
    abort("CSV not found at #{path}")
  end

  begin
    Daru::DataFrame.from_csv(path)
    return path
  rescue CSV::InvalidEncodingError, CSV::MalformedCSVError, ArgumentError => e
    warn "Initial CSV read failed: #{e.class}: #{e.message}. Attempting to clean encoding/newlines..."
  end

  raw = File.binread(path)
  encodings_to_try = ['UTF-8', 'Windows-1252', 'ISO-8859-1', 'ASCII']

  encodings_to_try.each do |enc|
    begin
      decoded = raw.force_encoding(enc).encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
      decoded = decoded.gsub("\r\n", "\n").gsub("\r", "\n")
      decoded = decoded.chars.map { |ch| (ch == "\n" || ch == "\t" || ch.ord >= 32) ? ch : ' ' }.join
      tmp = File.join(OUT_DIR, "stores_sales_forecasting.cleaned.#{enc}.csv")
      File.write(tmp, decoded, mode: "w", encoding: "utf-8")
      begin
        CSV.parse(decoded, headers: true)
        warn "Successfully cleaned using #{enc} -> wrote #{tmp}"
        return tmp
      rescue CSV::MalformedCSVError, CSV::Parser::InvalidEncoding => inner
        warn "Parsing still failed after using #{enc}: #{inner.class}: #{inner.message}"
      end
    rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError => enc_err
      warn "Encoding attempt #{enc} failed: #{enc_err.message}"
    end
  end

  fallback = raw.decode('utf-8', invalid: :replace, undef: :replace)
  fallback = fallback.gsub("\r\n", "\n").gsub("\r", "\n")
  tmp = File.join(OUT_DIR, "stores_sales_forecasting.fallback.csv")
  File.write(tmp, fallback, mode: "w", encoding: "utf-8")
  warn "Fallback cleaning applied, wrote #{tmp}"
  tmp
end

def load_and_aggregate(path)
  safe_path = ensure_utf8_csv(path)
  puts "Loading (post-clean) #{safe_path} ..."
  df = Daru::DataFrame.from_csv(safe_path)

  unless df.vectors.include?(DATE_COL) && df.vectors.include?(SALES_COL)
    warn "Available columns: #{df.vectors.to_a.inspect}"
    abort("CSV does not contain expected columns: '#{DATE_COL}' and '#{SALES_COL}'")
  end

  parsed_dates = df[DATE_COL].map do |v|
    begin
      Date.parse(v.to_s)
    rescue
      nil
    end
  end
  df.add_vector("#{DATE_COL}_parsed", Daru::Vector.new(parsed_dates))

  df_filtered = df.where(df["#{DATE_COL}_parsed"].not_eq(nil))
  grouped = Hash.new(0.0)
  df_filtered.each_row do |row|
    d = row["#{DATE_COL}_parsed"]
    s = begin
          Float(row[SALES_COL])
        rescue
          0.0
        end
    grouped[d] += s
  end

  dates = grouped.keys.sort
  values = dates.map { |d| grouped[d] }
  [dates, values]
end

def create_lags(series, lags)
  features = []
  targets = []
  (lags...series.size).each do |i|
    row = (1..lags).map { |lag| series[i - lag].to_f }
    features << row
    targets << series[i].to_f
  end
  [features, targets]
end

def train_and_predict(x_train, y_train, x_test, n_estimators:, max_depth:)
  model = Rumale::Ensemble::RandomForestRegressor.new(n_estimators: n_estimators, max_depth: max_depth, random_seed: 1)
  model.fit(x_train, y_train)
  preds = model.predict(x_test)
  [model, preds]
end

def metrics(y_true, y_pred)
  y_true_arr = y_true.respond_to?(:to_a) ? y_true.to_a : y_true
  y_pred_arr = y_pred.respond_to?(:to_a) ? y_pred.to_a : y_pred
  n = y_true_arr.length.to_f
  mae = y_true_arr.zip(y_pred_arr).map { |a, p| (a - p).abs }.sum / n
  rmse = Math.sqrt(y_true_arr.zip(y_pred_arr).map { |a, p| (a - p)**2 }.sum / n)
  { mae: mae, rmse: rmse }
end

# Main
puts "Using DATA_PATH = #{DATA_PATH}"
dates, series = load_and_aggregate(DATA_PATH)
puts "Series length: #{series.size} days (#{dates.first} .. #{dates.last})"

features, targets = create_lags(series, LAGS)
abort("Not enough data to create lag features. Reduce LAGS (#{LAGS}) or provide more data.") if features.empty?

x = Numo::DFloat[*features]
y = Numo::DFloat[*targets]

n_samples = x.shape[0]
train_size = (TRAIN_FRAC * n_samples).floor
if train_size <= 0 || train_size >= n_samples
  abort("Invalid TRAIN_FRAC resulting in train_size=#{train_size} for n_samples=#{n_samples}")
end

n_features = x.shape[1]
x_train = x[0...train_size, 0...n_features].dup
x_test  = x[train_size...n_samples, 0...n_features].dup
y_train = y[0...train_size].dup
y_test  = y[train_size...n_samples].dup

puts "Train size: #{y_train.size}, Test size: #{y_test.size}"
puts "Model params: n_estimators=#{MODEL_N_ESTIMATORS}, max_depth=#{MODEL_MAX_DEPTH}, lags=#{LAGS}"

model, preds = train_and_predict(x_train, y_train, x_test,
                                n_estimators: MODEL_N_ESTIMATORS,
                                max_depth: MODEL_MAX_DEPTH)

m = metrics(y_test, preds)
puts "Evaluation -> MAE: #{m[:mae].round(4)}, RMSE: #{m[:rmse].round(4)}"

test_start_index = LAGS + train_size
CSV.open(File.join(OUT_DIR, "forecast.csv"), "w") do |csv|
  csv << ["date", "actual", "predicted"]
  (0...y_test.length).each do |i|
    csv << [dates[test_start_index + i].to_s, y_test[i].to_f, preds[i].to_f]
  end
end

metrics_out = {
  model: { n_estimators: MODEL_N_ESTIMATORS, max_depth: MODEL_MAX_DEPTH, lags: LAGS },
  metrics: m,
  rows: series.size,
  train_size: train_size,
  test_size: y_test.size
}
File.write(File.join(OUT_DIR, "metrics.json"), JSON.pretty_generate(metrics_out))

puts "Forecast saved: #{OUT_DIR}/forecast.csv"
puts "Metrics saved: #{OUT_DIR}/metrics.json"
