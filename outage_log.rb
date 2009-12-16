#!/usr/bin/ruby

# parse and log power outages based on data from a connected APC UPS
# generate ATOM feed of recent outages

require 'ftools'
require 'tempfile'
require 'time'

require 'rubygems'
require 'atom'

LogFile = '/home/mmb/log/power_outage.log'
FeedFile = '/home/mmb/log/power_outage.atom'

def format_outage(d)
  last_batt_duration = d['XOFFBATT'] - d['XONBATT']
  "#{d['XONBATT']}|power outage for #{last_batt_duration} seconds"
end

time_fields = %w{
APC
DATE
LASTSTEST
MANDATE
STARTTIME
XOFFBATT
XONBATT
}

h = {}

IO.popen('/sbin/apcaccess') do |p|
  p.read.scan(/(\w+)\s*:\s*(.*)/) do |k,v|
    v = Time.parse(v) if time_fields.include?(k)
    h[k] = v
  end
end

last_outage = format_outage(h)

f = open(LogFile, 'a+')

updated = false
if f.eof? or ((last_line = f.readline.strip) != last_outage)
  tf = Tempfile.new('outage_rss')
  tf.write("#{last_outage}\n")
  tf.write("#{last_line}\n") unless (last_line || '').strip.empty?
  f.each { |line| tf.write("#{line}") unless line.strip.empty? }
  f.close
  tf.close
  File.copy(tf.path, LogFile)
  updated = true
else
  f.close
end

# update feed
if updated or !File.exists?(FeedFile)
  feed_lines = []
  open(LogFile) do |f|
    while feed_lines.size < 10 and !f.eof?
      line = f.readline.strip
      feed_lines.push(line) unless line.empty?
    end
  end

  feed = Atom::Feed.new do |f|
    f.title = 'Power Outages'
    feed_lines.each do |line|
      time, text = line.split('|')
      f.entries << Atom::Entry.new do |e|
        e.title = text
        e.updated = Time.parse(time)
        f.updated = [f.updated || Time.at(0), e.updated].max
        e.summary = text
      end
    end
  end

  open(FeedFile, 'w') { |f| f.write(feed.to_xml) }
end
