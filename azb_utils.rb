#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

#Created on Sun Aug 20 09:48:42 PM EDT 2023 
#author: Ryan Hildebrandt, github.com/ryancahildebrandt

#imports
require "httparty"
require "json"
require "tiny_segmenter"
require "duckdb"
require "ruby-progressbar"
require "erb"

#functions
# Processes one query lookup via the Jotoba API (https://jotoba.de/)
#
# @param query [String] Term to lookup
# @param target_reading [String] Reading to match for term, if not availabe in jotoba response, defaults to the first entry in the response
# @return [Hash] parsed api response, schema:
#   term: [String] query returned from api, may or may not be an exact match to query,
#   common: [Bool] is returned term marked as common by jotoba api?,
#   kana: [String] reading of term, in hiragana/katakana,
#   kanji: [String] writing of term including kanji,
#   furigana: [String] writing including kanji, annotated with furigana reading where applicable,
#   meaning: [String] definition of term,
#   info: [String] additional information pertaining to term
# @example jotoba_lookup("曇り")
#   {"term"=>"曇り", "common"=>true, "kana"=>"くもり", "kanji"=>"曇り", "furigana"=>"曇|くもり", "meaning"=>"cloudiness, cloudy weather", "info"=>nil}
# @see https://jotoba.de/docs.html#overview
def jotoba_lookup(query, target_reading)
    request = {
        :body => {
            "query" => query, 
            "language" => "English", 
            "no_english" => false
        }.to_json,
        :headers => {
            "content-type" => "application/json", 
            "accept" => "application/json"
        },
        :timeout => 60
    }
    response = api_query_check(query) ? HTTParty.post("https://jotoba.de/api/search/words", request).parsed_response : {"words" => []}
    
    if (response["words"].empty? || response["words"].nil?)
        out = {
            "term" => nil,
            "common" => nil,
            "kana" => nil,
            "kanji" => nil,
            "furigana" => nil,
            "meaning" => nil,
            "info" => nil
        }
    else
        response_word_index = response["words"].map{|x| x["reading"]["kana"]}.index(target_reading) || 0
        out = {
            "term" => query,
            "common" => response["words"][response_word_index]["common"],
            "kana" => response["words"][response_word_index]["reading"]["kana"],
            "kanji" => response["words"][response_word_index]["reading"]["kanji"],
            "furigana" => response["words"][response_word_index]["reading"]["furigana"].to_s.delete(']['),
            "meaning" => response["words"][response_word_index]["senses"][0]["glosses"].to_s.delete('"]['),
            "info" => response["words"][response_word_index]["senses"][0]["information"]
        }
    end
    return out
end

# Filters terms submitted to the jotoba_lookup function, removing terms that consist of a single kana or are of length 0
#
# @param query [String] Term to lookup
# @return [Bool] Whether query should be submitted to api
# @example api_query_check("曇り")
#   true
def api_query_check(query)
    return query.nil? ? false : !(query.length == 1 && %r{[ぁ-んァ-ン\u3000-\u303F\w]}.match?(query) || query.length == 0)
end

# Formats string containing given term, meaning, and reading for rendering furigana in html
#
# @param term [String] term to annotate
# @param reading [String] reading to place above term
# @param meaning [String] meaning to place below term
# @return [String] formatted ruby string for html rendering
# @example token_annotations("曇り", "曇|くもり", "cloudiness, cloudy weather")
#   "<ruby><rb>#{曇り}</rb><rt>#{曇|くもり}</rt><rtc>#{cloudiness, cloudy weather}</rtc></ruby>"
def token_annotations(term, reading, meaning)
    return "<ruby><rb>#{term}</rb><rt>#{reading}</rt><rtc>#{meaning}</rtc></ruby>"
end

# Formats html block with sidebyside annotations
#
# @param sentence [String] sentence to annotate
# @param annotation [String] annotation to place alongside sentence
# @param size_str [String] font style string to scale sentence text relative to annotation text
# @return [String] formatted html block
# @example sidebyside_block("曇り", "曇|くもり|cloudiness, cloudy weather", "150%")
#   "<div style = \"display: inline-block; width: 100%\">
#           <div class = \"column\" style = \"width: 20%; float: left; font-size: 150%\"><p>曇り</p></div>
#           <div class = \"column\" style = \"width: 80%; float: left\"><p>曇|くもり|cloudiness, cloudy weather</p></div>
#    </div>"
def sidebyside_block(sentence, annotation, size_str)
    return "
    <div style = \"display: inline-block; width: 100%\">
        <div class = \"column\" style = \"width: 20%; float: left; font-size: #{size_str}\"><p>#{sentence}</p></div>
        <div class = \"column\" style = \"width: 80%; float: left\"><p>#{annotation}</p></div>
    </div>
    "
end

# Formats html block with layered annotations
#
# @param sentence [String] sentence to annotate
# @param annotation [String] annotation to place alongside sentence
# @return [String] formatted html block
# @example sidebyside_block("曇り", "曇|くもり|cloudiness, cloudy weather")
#   "<div style = \"display: block; width: 100%;\">
#   <p>#{曇り}</p>
#   <p>#{曇|くもり|cloudiness, cloudy weather}</p>
#   </div>"
def layered_block(sentence, annotation)
    return "
    <div style = \"display: block; width: 100%;\">
    <p>#{sentence}</p>
    <p>#{annotation}</p>
    </div>
    "
end

# Formats html span for alternating annotations
#
# @param text [String] text to be sized
# @param size_str [String] font style string to scale text
# @return [String] formatted html span
# @example sized_span("曇り", "150%")
#   "<span style = \"font-size: 150%\">曇り</span>"
def sized_span(text, size_str)
    return "<span style = \"font-size: #{size_str}\">#{text}</span>"
end

# Converts output from furigana table to hash for use in lookup checking
#
# @param text [String] text to be sized
# @param size_str [String] font style string to scale text
# @return [String] formatted html span
# @example sized_span("曇り", "150%")
#   "<span style = \"font-size: 150%\">曇り</span>"
def process_furigana(db_result, segmenter)
	out = {}
	db_result.each do |context, reading|
		tok = segmenter.segment(context)
		key = tok[tok.index("（") - 1]
		val = reading[/[ぁ-んァ-ンヽゞゝ／″＼]+/]
		out[key] = val
	end
	return out
end

# classes
# AzbText class for storing and working with text information and annotation renderings
class AzbText
    attr_accessor(
        # @!attribute tagger
        #   @return [TinySegmenter] tinysegmenter tagger, used for tokenization
        :tagger,
        # @!attribute db
        #   @return [DuckDB::Connection] connection to duckdb database file at "data/aozora_corpus.db"
        :db,
        # @!attribute id
        #   @return [String] work id of selected text
        :id,
        # @!attribute title
        #   @return [String] title of selected text
        :title,
        # @!attribute author
        #   @return [String] author of selected text
        :author,
        # @!attribute n_char
        #   @return [Integer] length of selected text in number of characters
        :n_char,
        # @!attribute full_text
        #   @return [String] full text of selected text
        :full_text,
        # @!attribute furigana
        #   @return [Hash] furigana provided in azb text
        :furigana,
        # @!attribute lookups_file
        #   @return [String] path to lookups file of selected text, if already saved
        :lookups_file,
        # @!attribute lookups
        #   @return [Hash] lookup information for each token of selected text
        :lookups,
        # @!attribute unique_tokens
        #   @return [Array] all unique tokens occurring in the selected text
        :unique_tokens,
        # @!attribute sentence_data
        #   @return [Hash] information for each sentence in the full text, including tokens, lookups, tokens filtered by provided criteria, and annotation strings
        :sentence_data,
        # @!attribute output_prefix
        #   @return [String] path to rendered outputs
        :output_prefix, 
        # @!attribute alternating_annotations
        #   @return [String] html string for full text with alternating annotations
        :alternating_annotations,
        # @!attribute parallel_annotations
        #   @return [String] html string for full text with parallel annotations
        :parallel_annotations,
        # @!attribute layered_annotations
        #   @return [String] html string for full text with layered annotations
        :layered_annotations,
        # @!attribute sidebyside_annotations
        #   @return [String] html string for full text with side by side annotations
        :sidebyside_annotations,
        # @!attribute layered_plaintext
        #   @return [String] plain text string for full text with layered annotations
        :layered_plaintext,
        # @!attribute alternating_plaintext
        #   @return [String] plain text string for full text with alternating annotations
        :alternating_plaintext
    )
    
    def initialize
        self.tagger = TinySegmenter.new
        self.db = DuckDB::Database.open("data/aozora_corpus.db").connect
    end

    # Search aozora_corpus.db for works matching or containing search query
    #
    # @param query [String] query to search
    # @return [Array] all works containing query in work_id, work_name, author, subtitle, genre, or publication_date
    # @example 
    #   t = AzbText.new
    #   t.search("2009-01-25")
    #       ["047492", "キャラコさん", "十蘭久生", "07 海の刷画", "小説、物語", "2009-01-25"]
    #       ["047493", "キャラコさん", "十蘭久生", "08 月光曲", "小説、物語", "2009-01-25"]
    def search(query)
        base_query = "
        SELECT 作品ID, 作品名, 著者, 副題, 分類, 底本初版発行年1
        FROM works
        JOIN (
            SELECT 著者, 人物ID 
            FROM authors
        )
        USING (人物ID)
        WHERE
        作品ID LIKE '%#{query}%'
        OR
        作品名 LIKE '%#{query}%'
        OR 
        著者 LIKE '%#{query}%'
        OR 
        副題 LIKE '%#{query}%'
        OR 
        分類 LIKE '%#{query}%'
        OR 
        底本初版発行年1 LIKE '%#{query}%'
        "
        results = self.db.query(base_query)
        puts "Search results for query #{query}"
        puts "work_id | title | author | subtitle | genre | publication_date"
        results.entries.each { |entry| p entry}
    end
    
    # Loads information from text matching provided id
    #
    # @param work_id [String] work_id to match from aozora_corpus.db
    # @example 
    #   t = AzbText.new
    #   t.pull_text("047492")
    #       Text added successfully | ID: 047492 | Title: キャラコさん | Author: 十蘭久生 | Length: 14137
    def pull_text(work_id)
        text_query = "
        SELECT 作品ID, 作品名, 著者, 本文, 本文字数
        FROM works
        JOIN (
            SELECT 著者, 人物ID 
            FROM authors
        )
        USING (人物ID)
        JOIN (
            SELECT 作品ID, 本文, 本文字数 
            FROM texts
            WHERE 作品ID = '#{work_id}'
        )
        USING (作品ID)
        "
        valid_ids = self.db.query("SELECT 作品ID FROM works").entries.flatten
        if valid_ids.include?(work_id)
            results = self.db.query(text_query).entries.first
            self.id, self.title, self.author, self.full_text, self.n_char = results
            self.lookups_file = "data/#{self.id}_#{self.title}.json"
            self.output_prefix = "outputs/#{self.id}_#{self.title}"
            self.furigana = process_furigana(self.db.query("SELECT 前後関係, 振り仮名 FROM furigana WHERE 作品ID = '#{work_id}'").entries, self.tagger)
            puts "Text added successfully | ID: #{self.id} | Title: #{self.title} | Author: #{self.author} | Length: #{self.n_char}"
        else
            begin
                raise ArgumentError, "ID provided does not exist in database, please provide a valid 6 digit work_id"
            rescue => e
                puts "#{e.class} error: #{e.message}"
            end
        end      
    end

    # Lookups for tokens in text via jotoba api
    #
    # @example
    #   t = AzbText.new
    #   t.pull_text("047492")
    #   t.lookup_tokens
    #       [lookup progress bar]
    def lookup_tokens
        self.unique_tokens = self.tagger.segment(self.full_text).uniq
        self.lookups = {}
        progressbar = ProgressBar.create(
            :title => "Token lookup progress", 
            :total => self.unique_tokens.length, 
            :progress_mark => "・", 
            :format => "%t: %c/%C |%B| %p%%"
        )
        self.unique_tokens.each do |term|
            self.lookups[term] = jotoba_lookup(term, self.furigana[term])
            progressbar.increment
        end
    end
    
    # Exports lookups to json file for later reloading if necessary
    #
    # @example
    #   t = AzbText.new
    #   t.pull_text("047492")
    #   t.lookup_tokens
    #   t.save_lookups_to_file
    #       Annotations written to data/047492_キャラコさん.json
    def save_lookups_to_file
        File.write(self.lookups_file, self.lookups.to_json)
        puts "Annotations written to #{self.lookups_file}"
    end
    
    # Loads lookups from corresponding json file, if available
    #
    # @example
    #   t = AzbText.new
    #   t.pull_text("047492")
    #   t.lookup_tokens
    #   t.save_lookups_to_file
    #       Annotations loaded from data/047492_キャラコさん.json
    def load_lookups_from_file
        self.lookups = JSON.parse(File.read(self.lookups_file))
        puts "Annotations loaded from #{self.lookups_file}"
    end

    # Handles the lookup/load/save logic for text lookups depending on whether a corresponding lookup file exists in the expected location
    #
    # @example
    #   t = AzbText.new
    #   t.pull_text("047492")
    #   t.populate_lookups
    def populate_lookups
        if File.exist?(self.lookups_file)
            self.unique_tokens = self.tagger.segment(self.full_text).uniq
            self.load_lookups_from_file
        else
            self.lookup_tokens
            self.save_lookups_to_file
        end
    end

    # Applies lookup information to tokens in text for annotations
    #
    # @param exclude_common [Bool] whether to only render annotations for terms containing one or more kanji characters
    # @param kanji_only [Bool] whether to exclude common terms from rendered annotations, as defined by the jotoba api
    # @example
    #   t = AzbText.new
    #   t.pull_text("047492")
    #   t.populate_lookups
    #   t.annotate_text(true, false)
    def annotate_text(exclude_common = false, kanji_only = false)
        sentence_texts = self.full_text.split(/(?<=[。！？])/)
        self.sentence_data = {}
        sentence_texts.each_with_index do |sentence, index|
            tokens = self.tagger.segment(sentence)

            filtered_tokens = tokens.select{|term| !self.lookups[term].nil?}
            filtered_tokens = exclude_common ? filtered_tokens.select{|entry| !self.lookups[entry]["common"]} : filtered_tokens
            filtered_tokens = kanji_only ? filtered_tokens.select{|entry| %r{[一-龯]}.match?(entry)} : filtered_tokens

            token_lookups = self.lookups.select{|key, value| filtered_tokens.include? key}
            token_info_str = filtered_tokens.select{|term| !token_lookups[term]["term"].nil?}.map{|term| [term, "[#{term};#{token_lookups[term]["furigana"]};#{token_lookups[term]["meaning"]}]"]}.to_h

            self.sentence_data[index] = {
                "sentence" => sentence,
                "tokens" => tokens,
                "filtered_tokens" => filtered_tokens,
                "token_lookups" => token_lookups,
                "token_info_str" => token_info_str
            }
        end
    end

    # Formats html and plain text strings for all annotation styles, using size_str for font scaling if provided
    #
    # @param size_str [String] CSS string used to scale text size where applicable, either percent (125%), pixels (61px), or em (1.1em)
    # @example
    #   t = AzbText.new
    #   t.pull_text("047492")
    #   t.populate_lookups
    #   t.annotate_text(true, false)
    #   t.render_annotations("175%")
    # @note Font scaling only applies to alternating, layered, and sidebyside annotations in html format
    def render_annotations(size_str = "100%")
        self.sentence_data.each do |key, value|
            value["alternating_annotations"] = value["tokens"].map{|term| "#{sized_span(term, size_str)}#{value["token_info_str"][term]}"}
            value["parallel_annotations"] = value["tokens"].map{|term| token_annotations(term, value["token_lookups"][term]&.fetch("furigana", ""), value["token_lookups"][term]&.fetch("meaning", ""))}
            value["layered_annotations"] = layered_block(sized_span(value["sentence"], size_str), value["token_info_str"].values.join)
            value["sidebyside_annotations"] = sidebyside_block(value["sentence"], value["token_info_str"].values.join, size_str)
            value["alternating_plaintext"] = value["tokens"].map{|term| "#{term}#{value["token_info_str"][term]}"}
            value["layered_plaintext"] = "#{value["sentence"]}\n\n#{value["token_info_str"].values.join}"
        end
        
        self.alternating_annotations = self.sentence_data.map{|key, val| val["alternating_annotations"]}
        self.parallel_annotations = self.sentence_data.map{|key, val| val["parallel_annotations"]}
        self.layered_annotations = self.sentence_data.map{|key, val| val["layered_annotations"]}
        self.sidebyside_annotations = self.sentence_data.map{|key, val| val["sidebyside_annotations"]}
        self.alternating_plaintext = self.sentence_data.map{|key, val| val["alternating_plaintext"]}
        self.layered_plaintext = self.sentence_data.map{|key, val| val["layered_plaintext"]}
    end
    
    # Saves all annotations to html and plaintext formats as applicable
    #
    # @example
    #   t = AzbText.new
    #   t.pull_text("047492")
    #   t.populate_lookups
    #   t.annotate_text(true, false)
    #   t.render_annotations("175%")
    #   t.export_documents
    # @note Plaintext files will be generated for alternating, layered, and unannotated annotations, html for all annotations
    def export_documents
        title = self.title
        full_text = self.full_text
        text_info = "Written by #{self.author}, #{self.n_char} characters in length"
        
        alternating_annotations = self.alternating_annotations
        sidebyside_annotations = self.sidebyside_annotations
        parallel_annotations = self.parallel_annotations
        layered_annotations = self.layered_annotations
        
        ["alternating", "layered", "parallel", "sidebyside", "unannotated"].each do |anno|
            template = File.read("templates/#{anno}.erb.html")
            result = ERB.new(template).result(binding)
            outfile = "#{self.output_prefix}_#{anno}.html"
            File.open(outfile, 'w+').write(result)
            puts "Text exported to #{outfile}"
        end
        
        alternating_plaintext = self.alternating_plaintext
        layered_plaintext = self.layered_plaintext
        
        ["alternating", "layered", "unannotated"].each do |anno|
            template = File.read("templates/#{anno}.erb.txt")
            result = ERB.new(template).result(binding)
            outfile = "#{self.output_prefix}_#{anno}.txt"
            File.open(outfile, 'w+').write(result)
            puts "Text exported to #{outfile}"
        end
    end
end

