#!/usr/bin/env ruby

require 'optparse'
require 'stringio'
require 'fileutils'
require_relative 'types'

opts = Struct.new(:filter, :merge, :stats, :restrict, :old).new
OptionParser.new do |opt|

    opt.on('-h', '--help', 'outputs this help message') do
        puts opt
        exit
    end

    opt.on('-fNAME', '--filter=NAME', 'file to output filtered sequences to') do |f|
        opts.filter = f
    end

    opt.on('-mNAME', '--merge=NAME', 'file to remerge into seqs') do |m|
        opts.merge = m
    end

    opt.on('-sLEVEL', '--stats=LEVEL', 'level to compute call stats for') do |s|
        opts.stats = s
    end

    opt.on('-rLEVEL', '--restrict=LEVEL', 'level to restrict to') do |r|
        opts.restrict = r
    end

    opt.on('-o', '--old', 'include old sequences') do |o|
        opts.old = true
    end

end.parse!

def filt seq, opts
    return false if seq.tags.any?{|tag|
        tag[0] == ?! || %w[bad sus worse].include?(tag)
        # tag[0] == ?! || %w[bad sus worse].include?(tag)
    }

    return false if opts.restrict && !seq.tags.include?(opts.restrict)
    return false if !opts.old && seq.tags.any?{|tag| tag[0] == ?@ }

    return true
end

abort 'no seqs' unless File.exists?('seqs')
allseqs = File.open('seqs', ?r) do |f| fromtxt f end
seqs = allseqs.filter{|seq| filt seq, opts }

if opts.filter
    if opts.filter == '-'
        totxt STDOUT, seqs, {}
    else
        File.open(opts.filter, ?w) do |f|
            totxt f, seqs, {}
        end
    end
    puts "#{seqs.size} sequences filtered"
end

if opts.merge
    nmerge = 0
    File.open(opts.merge, ?r){|f| fromtxt f }.each do |seq|
        idx = allseqs.index{|s2| seq.date == s2.date}
        abort "couldn't find #{seq.date} in seqs" unless idx
        allseqs[idx] = seq
        nmerge += 1
    end
    FileUtils.mkdir_p 'bkp'
    FileUtils.cp 'seqs', "bkp/seqs-#{Time.new.strftime '%F_%T'}"
    File.open('seqs', ?w) do |g|
        totxt g, allseqs, {}
    end
    puts "#{nmerge} sequences merged"
end

if opts.stats
    cnt = {}
    seqs.each do |seq|
        next unless seq.tags.include? opts.stats
        seq.calls.each do |call|
            unless f = call.formal
                # p call
                next
            end
            f.split.each do |w|
                cnt[w] = (cnt[w]||0)+1
            end
        end
    end

    $db.entries.each do |e|
        next unless e.lvl == opts.stats.downcase
        puts "#{cnt[e.formal]} #{e.formal}"
    end
end

if ARGV.include? 'summary'
    cnts = $lvl.map{|x|[x,0]}.to_h
    seqs.each do |seq|
        cnts[(seq.tags & $lvl)[0]] += 1
    end
    p cnts
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

if ARGV.include? 'prod'
    totxt STDOUT, seqs, {mode: :prod}
end

if ARGV.include? 'level'
    seqs.each do |seq|
        puts "#{seq.name} #{seq.tags*' '}"
        puts seq.calls.flat_map{|call|
            call.formal ? call.formal.split.map{|x| $db.lookup[x] ? $db.lookup[x].lvl : nil}.compact : []
        }.join ' '
    end
end
