require 'bibtex'

# Remove 'url' if 'doi' is present
def remove_redundant_url(bib)
  bib.each do |entry|
    if entry.has_field?('doi') && entry.has_field?('url')
      entry.delete('url')
    end
  end
end

# Load BibTeX
bibfile = "bibliography.bib"
bib = BibTeX.open(bibfile)

remove_redundant_url(bib)

# Overwrite the original file
output_file = "bibliography.bib"
File.open(output_file, 'w') { |f| f.write(bib.to_s) }

puts "BibTeX file #{output_file} has been updated"
