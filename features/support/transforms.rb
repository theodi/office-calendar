DATETIME = Transform /^(\d+)\-(\d+)\-(\d+) (\d+):(\d+)$/ do |year, month, day, hour, minute|
  DateTime.new(year.to_i, month.to_i, day.to_i, hour.to_i, minute.to_i)
end

DATE = Transform /^(\d+)\-(\d+)\-(\d+)$/ do |year, month, day|
  Date.new(year.to_i, month.to_i, day.to_i)
end