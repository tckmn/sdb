#!/usr/bin/env ruby

require 'date'
require 'fileutils'
require_relative 'types'

seqs = File.exists?($FILE) ? File.open($FILE, ?r) do |f|
     fromtxt f
end : []

def frac s
    n, d = s.split(?/).map &:to_i
    (8 * n / d).to_s
end

sd2real = {
    'MS'   => 'ms',
    'Plus' => 'plus',
    'A1'   => 'a1',
    'A2'   => 'a2',
    'C1'   => 'c1',
    'C2'   => 'c2',
    'C3A'  => 'c3a',
    'C3'   => 'c3b',
    'C4'   => 'c4',
    'all'  => 'all'
}

snew = 0
sold = 0
sfail = 0
sdates = seqs.map{|seq| seq.date}

Dir['in/*'].each do |fname|
File.read(fname).split("\x0c").each do |sdseq|

    metadata, *chunks, resolve = sdseq.gsub("\r\n", "\n").split("\n\n").map{|x| x.strip.lines.map(&:strip)}

    if metadata[1] == 'NOT RESOLVED'
        # TODO maybe crosscheck with rline==nil
        metadata.delete_at 1
        chunks.pop while chunks[-1][0] =~ /[1234][GB][<>V^]/
    end

    date = DateTime.parse(metadata[0].split('     ')[0]).strftime('%F %T')
    name = metadata[1..-1].join ' '
    if sdates.include? date
        sold += 1
        next
    end
    snew += 1

    opener = if chunks[0] == ['From squared set']
        # chunks[0] = ['just as they are']
        chunks.shift
        'J'
    elsif chunks[0][0] =~ /^(HEADS|SIDES) /
        # chunks.unshift [chunks[0][0][0..4].downcase + ' start']
        r = chunks[0][0][0]
        chunks[0][0] = chunks[0][0][6..-1]
        r
    else
        puts "#{date} is bad"
        snew -= 1
        sfail += 1
        next
    end

    rline = resolve[0] ? resolve[0].sub('approximately ', '') : nil
    closer = if !rline
        '--'
    elsif rline == 'at home'
        'N0'
    elsif rline =~ /^circle left (.*) or right .*$/
        'C' + frac($1)
    elsif rline =~ /^(.*)  \((?:(.*) promenade|at home)/
        {
            'right and left grand' => ?R,
            'mini-grand' => ?M,
            'left allemande' => ?L,
            'promenade' => ?P,
            'reverse promenade' => ?E,
            'single file promenade' => ?S,
            'reverse single file promenade' => ?F,
            'dixie grand, left allemande' => ?D
        }[$1] + ($2 ? frac($2) : ?0)
    end

    tcl = false
    tags = ['generated', sd2real[fname.split(?.)[-1]]]
    [tags.push($1), (name = $')] while name =~ /^\[([^\]]+)\] /
    seq = Sequence.new opener+closer, date, tags, name,
        chunks.map{|ch|
            tcl = true if ch.include? 'Warning:  This concept is not allowed at this level.'
            Call.new ch.take_while{|x| !x.start_with?('Warning:') }.join(' ')
        }
    seq.periphery += ?+ if tcl

    seqs.push seq

end
end

FileUtils.mkdir_p 'bkp'
FileUtils.cp $FILE, "bkp/seqs-#{Time.new.strftime '%F_%T'}"
File.open($FILE, ?w) do |f|
    totxt f, seqs, {}
end
puts "#{seqs.size} sequences written (#{snew} new, #{sold} old, #{sfail} failed)"
