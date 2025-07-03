#! /usr/bin/env ruby
require 'nokogiri'
require 'net/http'
require 'pathname'
require 'open-uri'

def random_ip
  loop do
    ip = [
      rand(1..223),
      rand(0..255),
      rand(0..255),
      rand(1..254)
    ]
    return ip.join('.') unless [10, 127, 169, 172, 192].include?(ip[0])
  end
end

def random_user_agent
  ip = random_ip
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64; IP=#{ip}) " \
  "AppleWebKit/537.36 (KHTML, like Gecko) " \
  "Chrome/#{ip} Safari/537.36"
end

def download_html(url)
  URI.open(url,
  'User-Agent' => random_user_agent,
  'Accept-Language' => 'en-US,en;q=0.9',
  'Accept' => 'text/html,application/xhtml+xml'
) { |resp| Nokogiri::HTML(resp.read) }
end

def generate_scholar_tex
#   scholar_url = 'https://scholar.google.com/citations?user=iJDPEaUAAAAJ&hl=en'
  scholar_url = 'https://scholar.google.it/citations?user=iJDPEaUAAAAJ&hl=it&oi=ao'
  scholar_page = download_html(scholar_url)
  return false unless scholar_page

  since = scholar_page.xpath('//*[@class="gsc_rsb_sth"]')
                      .map(&:text)
                      .find { |text| text.include?('Since') }

  cited_by = scholar_page.xpath('//*[@class="gsc_rsb_std"]').map(&:text)
  return false unless cited_by.length >= 6

  tex = <<-TeX
% !TeX root = curriculum.tex
\\textbf{\\href{#{scholar_url}}{Google Scholar metrics as of #{Time.now.strftime('%Y-%m-%d')}}}
\\medskip
\\centering
\\begin{minipage}{.4\\textwidth}
    \\begin{outerlist}
        \\item[] Overall
        \\begin{innerlist}
            \\item Citations: #{cited_by[0]}
            \\item h-Index: #{cited_by[2]}
            \\item i10-Index: #{cited_by[4]}
        \\end{innerlist}
    \\end{outerlist}
\\end{minipage}
\\hfill
\\begin{minipage}{.4\\textwidth}
    \\begin{outerlist}
        \\item[] #{since}
        \\begin{innerlist}
            \\item Citations: #{cited_by[1]}
            \\item h-Index: #{cited_by[3]}
            \\item i10-Index: #{cited_by[5]}
        \\end{innerlist}
    \\end{outerlist}
\\end{minipage}
\\vspace{1em}
  TeX

  File.write('scholar.tex', tex)
  puts "✓ 'scholar.tex' creato con successo."
  true
end

# Retry loop in CI

# If the file 'scholar.tex' exists, remove it
File.delete('scholar.tex') if File.exist?('scholar.tex')

max_attempts = 3
attempt = 1
until File.exist?('scholar.tex') || attempt > max_attempts
  puts "Tentativo #{attempt} di generazione 'scholar.tex'..."
  break if generate_scholar_tex

  attempt += 1
  sleep 30 if attempt <= max_attempts
end

unless File.exist?('scholar.tex')
  puts "✗ Fallita la generazione di 'scholar.tex' dopo #{max_attempts} tentativi."
  exit 1
end
