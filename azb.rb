#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

#Created on Wed Sep 13 12:07:22 PM EDT 2023 
#author: Ryan Hildebrandt, github.com/ryancahildebrandt

# imports
require "optparse"

require_relative "azb_utils"

options = {
	"common" => false,
	"kanji" => false,
	"fontstring" => "100%"
}

OptionParser.new do |opts|
	opts.banner = "AozoraBunko Annotator Script"
	opts.separator "\n\nUSAGE\n"
	opts.on("-s", "--search QUERY", String, "Search query to be compared against the work_id, work_name, and author fields. Returns partial or complete matches from available texts"){|q| options["query"] = q}
	opts.on("-f", "--font-string SIZE", String, "CSS string used to scale text size where applicable, either percent (125%), pixels (61px), or em (1.1em)"){|f| options["fontstring"] = f}
	opts.on("-k", "--kanji-only", "Whether to only render annotations for terms containing one or more kanji characters"){|k| options["kanji"] = true}
	opts.on("-c", "--exclude-common", "Whether to exclude common terms from rendered annotations, as defined by the jotoba api"){|c| options["common"] = true}
	opts.on("-i", "--id WORK_ID", String, "6 digit text id, returned from the search function or https://www.aozora.gr.jp/"){|i| options["id"] = i}
	opts.on("-h", "--help", "Prints this help") do
		puts opts
		exit
	end
end.parse!

t = AzbText.new
if !options["query"].nil?
	t.search(options["query"])
elsif !options["id"].nil?
	t.pull_text(options["id"])
	t.populate_lookups
	t.annotate_text(options["common"], options["kanji"])
	t.render_annotations(options["fontstring"])
	t.export_documents
end