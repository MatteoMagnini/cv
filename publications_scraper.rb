#!/usr/bin/env ruby
require 'nokogiri'
require 'open-uri'

def download_html(url)
  begin
    Nokogiri::HTML(URI.open(url))
  rescue OpenURI::HTTPError => e
    puts "HTTP error when fetching #{url}: #{e.message}"
    nil
  rescue => e
    puts "Error when fetching #{url}: #{e.message}"
    nil
  end
end

def fetch_bibtex(publication_url)
  publication_page = download_html(publication_url)
  return nil unless publication_page

  # Trova il link BibTeX nella pagina della pubblicazione
  bibtex_link = publication_page.at_css('a[rel="nofollow"][href*="view=bibtex"]')
  return nil unless bibtex_link

  bibtex_url = bibtex_link['href']
  # Completa l'URL se necessario
  bibtex_url = URI.join(publication_url, bibtex_url).to_s

  bibtex_page = download_html(bibtex_url)
  return nil unless bibtex_page

  bibtex = bibtex_page.css('pre').text
  return bibtex
rescue => e
  puts "Error when fetching the BibTeX of #{publication_url}: #{e.message}"
  return nil
end

def generate_bib_file(author_url, output_file)
  author_page = download_html(author_url)
  return unless author_page

  publications = author_page.css('li.entry.inproceedings, li.entry.article')
  puts "#{publications.size} publications found"

  File.open(output_file, 'w') do |file|
    publications.each do |publication|
      publication_link = publication.at_css('a[href*="/rec/"]')
      next unless publication_link

      publication_url = publication_link['href']
      publication_url = URI.join(author_url, publication_url).to_s

      bibtex = fetch_bibtex(publication_url)
      if bibtex
        file.puts bibtex
        file.puts "\n"
      end
    end
  end

  puts "File BibTeX: #{output_file}"
end

author_url = 'https://dblp.uni-trier.de/pid/329/5724.html'
output_file = 'bibliography.bib'

generate_bib_file(author_url, output_file)
