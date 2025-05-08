#! /usr/bin/env ruby
require 'nokogiri'
require 'net/http'
require 'pathname'
require 'open-uri'

def download_html(url)
  URI.open(url,
  'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '\
                  'AppleWebKit/537.36 (KHTML, like Gecko) '\
                  'Chrome/113.0.0.0 Safari/537.36',
  'Accept-Language' => 'en-US,en;q=0.9',
  'Accept' => 'text/html,application/xhtml+xml'
) { |resp| Nokogiri::HTML(resp.read) }
end

#Scholar
scholar_page = download_html('https://scholar.google.com/citations?user=iJDPEaUAAAAJ&hl=en')
since = scholar_page.xpath('//*[@class="gsc_rsb_sth"]')
    .map { |tag| tag.text }
    .filter { |text| text.include?('Since') }
    .first
citedBy = scholar_page.xpath('//*[@class="gsc_rsb_std"]')
    .map {| tag | tag.text }
latex_newline = '\\\\'
tex = <<-TeX
% ! TeX root = curriculum.tex
\\textbf{\\href{https://scholar.google.com/citations?user=iJDPEaUAAAAJ&hl=en}{Google Scholar metrics as of #{Time.now.strftime('%Y-%m-%d')}}}
\\medskip
\\centering
\\begin{minipage}{.4\\textwidth}
    \\begin{outerlist}
        \\item[] Overall
        \\begin{innerlist}
            \\item Citations: #{citedBy[0]}
            \\item h-Index: #{citedBy[2]}
            \\item i10-Index: #{citedBy[4]}
        \\end{innerlist}
    \\end{outerlist}
\\end{minipage}
\\hfill
\\begin{minipage}{.4\\textwidth}
    \\begin{outerlist}
        \\item[] #{since}
        \\begin{innerlist}
            \\item Citations: #{citedBy[1]}
            \\item h-Index: #{citedBy[3]}
            \\item i10-Index: #{citedBy[5]}
        \\end{innerlist}
    \\end{outerlist}
\\end{minipage}
\\vspace{1em}
TeX
puts tex
File.write('scholar.tex', tex)

#Scopus
puts download_html('https://www.scopus.com/authid/detail.uri?authorId=57894531500')