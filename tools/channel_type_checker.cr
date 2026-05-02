#!/usr/bin/env crystal
# Simple heuristic checker: finds Channel declarations and reports send sites in project.
matches = {} of String => Array(String)

Dir.glob("**/*.cr") do |file|
  text = File.read(file)
  line_num = 0
  text.each_line do |line|
    line_num += 1
    if m = /Channel\(([^)]+)\)/.match(line)
      type = m[1].strip
      matches[file] ||= [] of String
      matches[file] << "#{line_num}: Channel(#{type})"
    end
  end
end

puts "Found Channel declarations:"
matches.each do |file, decls|
  puts "\n#{file}"
  decls.each { |decl| puts "  #{decl}" }
end

puts "\nSearching for .send( occurrences..."
send_sites = [] of Tuple(String, Int32, String)
Dir.glob("**/*.cr") do |file|
  line_num = 0
  File.read(file).each_line do |line|
    line_num += 1
    if line.includes?(".send(")
      send_sites << {file, line_num, line.strip}
    end
  end
end

puts "Found .send occurrences: #{send_sites.size}"
send_sites.each do |file_name, line_num, line_content|
  puts "#{file_name}:#{line_num}: #{line_content}"
end

puts "\nNote: This is a heuristic report. Review manually for channel type mismatches."
