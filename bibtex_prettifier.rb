require 'bibtex'

# Remove 'url' if 'doi' is present
def remove_redundant_url(bib)
  bib.each do |entry|
    if entry.has_field?('doi') && entry.has_field?('url')
      entry.delete('url')
    end
  end
end

def normalize_doi(doi)
  doi.to_s.strip.downcase
end

def normalize_title(title)
  title.to_s
       .gsub(/[{}]/, '')        # remove braces
       .downcase
       .gsub(/\s+/, ' ')        # collapse whitespace
       .strip
end

def remove_duplicates(bib)
  seen_dois = {}
  seen_titles = {}
  duplicates = []

  bib.each do |entry|
    doi = normalize_doi(entry['doi'])
    title = normalize_title(entry['title'])

    if !doi.empty?
      if seen_dois.key?(doi)
        duplicates << entry
      else
        seen_dois[doi] = entry
      end
    elsif !title.empty?
      if seen_titles.key?(title)
        duplicates << entry
      else
        seen_titles[title] = entry
      end
    end
  end

  duplicates.each { |entry| bib.delete(entry) }
end

# Load BibTeX
bibfile = "bibliography.bib"
bib = BibTeX.open(bibfile)

remove_redundant_url(bib)
remove_duplicates(bib)

# Overwrite the original file
output_file = "bibliography.bib"
File.open(output_file, 'w') { |f| f.write(bib.to_s) }

puts "BibTeX file #{output_file} has been updated (duplicates removed)"