#!/usr/bin/env ruby

require 'date'
require_relative 'types'

DEBUG = true

$FILE = 'seqs'

seqs = !DEBUG && File.exists?($FILE) ? File.open($FILE, ?r) do |f|
     fromtxt f
end : []

def frac s
    n, d = s.split(?/).map &:to_i
    (8 * n / d).to_s
end

File.read(DEBUG ? 'debug' : 'sequence.C1').split("\x0c").each do |sdseq|

    metadata, *chunks, resolve = sdseq.split("\r\n\r\n").map{|x| x.strip.lines.map(&:strip)}

    if metadata[1] == 'NOT RESOLVED'
        # TODO maybe crosscheck with rline==nil
        metadata.delete_at 1
        chunks.pop while chunks[-1][0] =~ /[1234][GB][<>V^]/
    end

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
        abort 'what'
    end

    rline = resolve[0] ? resolve[0].sub('approximately ', '') : nil
    closer = if !rline
        '--'
    elsif rline == 'at home'
        'N0'
    elsif rline =~ /^circle left (.*) or right .*$/
        'C' + frac($1)
    elsif rline =~ /^(.*)  \((?:(.*) promenade|at home)\)$/
        {
            'right and left grand' => ?R,
            'left allemande' => ?L,
            'promenade' => ?P,
            'reverse promenade' => ?E,
            'dixie grand, left allemande' => ?D
        }[$1] + ($2 ? frac($2) : ?0)
    end

    tcl = false
    seq = Sequence.new opener+closer,
        DateTime.parse(metadata[0].split('     ')[0]).strftime('%F %T'),
        ['generated'], metadata[1..-1].join(' '),
        chunks.map{|ch|
            tcl = true if ch.include? 'Warning:  This concept is not allowed at this level.'
            Call.new ch.take_while{|x| !x.start_with?('Warning:') }.join(' ')
        }
    seq.periphery += ?+ if tcl

    seqs.push seq

end

File.open($FILE, ?w) do |f|
    totxt f, seqs
end
