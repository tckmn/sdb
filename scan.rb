#!/usr/bin/env ruby

require 'date'
require_relative 'types'

DEBUG = true

$FILE = 'seqs'

seqs = !DEBUG && File.exists?($FILE) ? File.open($FILE, ?r) do |f|
     fromtxt f
end : []

File.read(DEBUG ? 'debug' : 'sequence.C1').split("\x0c").each do |sdseq|

    metadata, *chunks, resolve = sdseq.split("\r\n\r\n").map{|x| x.strip.lines.map(&:strip)}

    if metadata[1] == 'NOT RESOLVED'
        metadata.delete_at 1
        chunks.pop while chunks[-1][0] =~ /[1234][GB][<>V^]/
    end

    if chunks[0] == ['From squared set']
        chunks[0] = ['just as they are']
    elsif chunks[0][0] =~ /^(HEADS|SIDES) /
        chunks.unshift [chunks[0][0][0..4].downcase + ' start']
        chunks[1][0] = chunks[1][0][6..-1]
    else
        abort 'what'
    end

    seq = Sequence.new DateTime.parse(metadata[0].split('     ')[0]).strftime('%F %T'),
        ['generated'], metadata[1..-1].join(' '),
        chunks.map{|ch| Call.new ch.take_while{|x| !x.start_with?('Warning:') }.join(' ') }

    seqs.push seq

end

File.open($FILE, ?w) do |f|
    totxt f, seqs
end
