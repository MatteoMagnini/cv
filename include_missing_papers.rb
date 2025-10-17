#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'

MAIN_BIB = 'bibliography.bib'
BIB_DIR  = 'bibtex'

# Parse all BibTeX entries from a text block
def parse_bib_entries(text)
  text.scan(/@(\w+)\s*\{[^@]*?\}\s*(?=@|\z)/m)
      .map { |_,| Regexp.last_match[0] }
end

# Extract and normalize title and DOI
def extract_title_and_doi(entry)
  title = entry[/title\s*=\s*\{(.*?)\}/im, 1]
  doi   = entry[/doi\s*=\s*\{(.*?)\}/im, 1]
  normalized_title = title&.downcase&.gsub(/[^a-z0-9]/, '')
  [normalized_title, doi&.strip]
end

# Load existing entries from the main .bib file
def load_existing_entries
  existing = File.exist?(MAIN_BIB) ? File.read(MAIN_BIB) : ''
  parse_bib_entries(existing).map { |entry| extract_title_and_doi(entry) }
end

# --- MAIN SCRIPT ---

existing_entries = load_existing_entries
new_entries = []

Dir.glob(File.join(BIB_DIR, '*.bib')).each do |bibfile|
  puts "→ Scanning #{bibfile}"
  content = File.read(bibfile)
  parse_bib_entries(content).each do |entry|
    title, doi = extract_title_and_doi(entry)
    next unless title # skip entries without title

    duplicate = existing_entries.any? do |et, ed|
      (doi && ed && doi.casecmp(ed).zero?) || (et && (title.include?(et) || et.include?(title)))
    end

    unless duplicate
      new_entries << entry.strip
      existing_entries << [title, doi]
      puts "   + Added: #{title&.slice(0, 60)}..."
    end
  end
end

if new_entries.empty?
  puts '✅ No new entries to add.'
else
  File.open(MAIN_BIB, 'a') do |f|
    f.puts "\n\n% --- Automatically added entries ---"
    new_entries.each { |e| f.puts "\n#{e}\n" }
  end
  puts "✅ Added #{new_entries.size} new entries to #{MAIN_BIB}"
end
