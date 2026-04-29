#!/usr/bin/env crystal
# Simple heuristic checker: finds Channel declarations and reports send sites in project.
matches = {} of String => Array(String)

Dir.glob("**/*.cr") do |file|
  text = File.read(file)
  text.each_line.with_index(1) do |line, ln|
    if m = /Channel\(([^)]+)\)/.match(line)
      type = m[1].strip
      matches[file] ||= [] of String
      matches[file] << "#{ln}: Channel(#{type})"
    end
  end
end

puts "Found Channel declarations:"
matches.each do |file, decls|
  puts "\n#{file}"
  decls.each { |d| puts "  #{d}" }
end

puts "\nSearching for .send( occurrences..."
send_sites = [] of Tuple(String, Int32, String)
Dir.glob("**/*.cr") do |file|
  File.read(file).each_line.with_index(1) do |line, ln|
    if line.includes?(".send(")
      send_sites << {file, ln, line.strip}
    end
  end
end

puts "Found .send occurrences: #{send_sites.size}"
send_sites.each do |f, ln, l|
  puts "#{f}:#{ln}: #{l}"
end

puts "\nNote: This is a heuristic report. Review manually for channel type mismatches."
