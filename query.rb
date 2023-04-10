#!/usr/bin/env ruby

require 'optparse'
require_relative 'types'

opts = {}
OptionParser.new do |opt|

    opt.on('-h', '--help', 'outputs this help message') do
        puts opt
        exit
    end

end.parse!

abort 'no seqs' unless File.exists?('seqs')
seqs =  File.open('seqs', ?r) do |f| fromtxt f end

if ARGV.include? 'summary'
    cnts = $lvl.map{|x|[x,0]}.to_h
    seqs.each do |seq|
        next if seq.tags.any?{|tag|
            tag[0] == ?! || tag[0] == ?@ || %w[bad sus worse].include?(tag)
        }
        cnts[(seq.tags & $lvl)[0]] += 1
    end
    p cnts
end

if ARGV.include? 'stats2'
    cnt = {}
    seqs.each do |seq|
        next if seq.tags.any?{|tag|
            tag[0] == ?! || tag[0] == ?@ || %w[bad sus worse].include?(tag)
        }
        next unless seq.tags.include? 'C2'
        seq.calls.each do |call|
            next unless f = call.formal
            f.split.each do |w|
                cnt[w] = (cnt[w]||0)+1
            end
        end
    end

    $db.entries.each do |e|
        next unless e.lvl == 'c2'
        puts "#{cnt[e.formal]} #{e.formal}"
    end
end

if ARGV.include? 'stats'
    cnt = {}
    seqstr = ''
    seqs.each do |seq|
        seq.calls.each do |call|
            unless call.formal
                # p call
                next
            end
            seqstr += call.formal + "\n"
            next unless f = call.formal
            f.split.each do |w|
                cnt[w] = (cnt[w]||0)+1
            end
        end
    end
    %w[
        beaus|belles
        bracethru
        tripletrade
        grand\ followyourneighbor
        ./4thru
        wheelthru
        turn&deal
        pass(in|out)
        chainreaction
        (cross)?cloverand
        .
        mix
        splitsquarethru
        crossovercirculate
        step&slide
        lockit
        castashadow
        rolltoawave
        6by2aceydeucey
        1/4(in|out)
        partnertag
        &cross
        .
        passthesea
        explodeand
        swaparound
        pairoff
        ascouples
        transferthecolumn
        squarechainthru
        crosstrailthru
        horseshoeturn
        .
        endsbend
        scoot&dodge
        (double|triple)starthru
        ./[24]top
        cycle&wheel
        anyhand
        splitsquarechainthru
        (double|triple)cross
        .
        motivate
        singlewheel
        slip
        splitcounterrotate
        inrollcirculate
        scoot&weave
        tradecirculate
        switchthewave
    ].each do |x|
        if x == ?.
            puts
        else
            puts "#{seqstr.scan(/( |^)(#{x})( |$)/).size} #{x}"
        end
    end

    # $db.entries.each do |e|
    #     next unless e.lvl == 'c1'
    #     puts "#{cnt[e.formal] || 0} #{e.formal}"
    # end

    # $db.entries.each do |e|
    #     next unless %w[
    #         bracethru
    #         tripletrade
    #     ].include? e.formal
    #     puts "#{cnt[e.formal] || 0} #{e.formal}"
    # end
end

if ARGV.include? 'verbal'
    seqs.each do |seq|
        puts seq.verbal
    end
end

if ARGV.include? 'level'
    seqs.each do |seq|
        puts "#{seq.name} #{seq.tags*' '}"
        puts seq.calls.flat_map{|call|
            call.formal ? call.formal.split.map{|x| $db.lookup[x] ? $db.lookup[x].lvl : nil}.compact : []
        }.join ' '
    end
end
