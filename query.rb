#!/usr/bin/env ruby

require 'optparse'
require 'stringio'
require 'fileutils'
require_relative 'types'

def genrestrict r
    r = r[1...-1] while r[0] == ?( && r[-1] == ?)

    orpos = nil
    andpos = nil
    dpth = 0
    r.chars.each.with_index do |ch,idx|
        case ch
        when ?( then dpth += 1
        when ?) then dpth -= 1
        when ?| then orpos = idx if !orpos && dpth == 0
        when ?& then andpos = idx if !andpos && dpth == 0
        end
    end

    if !orpos && !andpos
        if r[0] == ?!
            f = genrestrict r[1..-1]
            return ->ts { !f[ts] }
        end
        return ->ts { ts.any?{|t| t == r || (t.start_with?(r) && t[r.size] == ?.) } }
    end

    pos = orpos || andpos
    f1 = genrestrict r[0...pos]
    f2 = genrestrict r[pos+1..-1]
    orpos ? ->ts { f1[ts] || f2[ts] } : ->ts { f1[ts] && f2[ts] }
end

opts = Struct.new(:filter, :merge, :stats, :class, :restrict, :old, :theme).new
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

    opt.on('-sLEVEL', '--stats=LEVEL', 'level(s) to compute call stats for') do |s|
        opts.stats = s
    end

    opt.on('-cNAME', '--class=NAME', 'class list for stats breakdown') do |c|
        opts.class = c
    end

    opt.on('-rLEVEL', '--restrict=LEVEL', 'level to restrict to') do |r|
        opts.restrict = genrestrict r.gsub(/\s/, '')
    end

    opt.on('-o', '--old', 'include old sequences') do |o|
        opts.old = true
    end

    opt.on('-tTHEME', '--theme=THEME', 'which theme pool to draw from') do |t|
        opts.theme = t
    end

end.parse!

def filt seq, opts
    return false if seq.tags.any?{|tag|
        (!opts.theme && tag[0] == ?!) || (!opts.old && tag[0] == ?@) || %w[bad skip sus worse todo].include?(tag)
    }

    return false if opts.restrict && !opts.restrict[seq.tags]
    return false if opts.theme && !t.include?(?!+opts.theme)

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

    if opts.merge[0] == ?@
        puts 'paste sdj data:'
        gets.chomp.split('.').filter{|d| d.size>0}.each do |d|
            idx = allseqs.index{|s2| d == s2.date}
            abort "couldn't find #{d} in seqs" unless idx
            allseqs[idx].tags.push opts.merge
            nmerge += 1
        end
    else
        File.open(opts.merge, ?r){|f| fromtxt f }.each do |seq|
            idx = allseqs.index{|s2| seq.date == s2.date}
            abort "couldn't find #{seq.date} in seqs" unless idx
            allseqs[idx] = seq
            nmerge += 1
        end
    end

    FileUtils.mkdir_p 'bkp'
    FileUtils.cp 'seqs', "bkp/seqs-#{Time.new.strftime '%F_%T'}"
    File.open('seqs', ?w) do |g|
        totxt g, allseqs, {}
    end

    puts "#{nmerge} sequences merged"
end

if opts.stats
    lvls = opts.stats.split ?,

    cnt = {}
    seqs.each do |seq|
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

    if opts.class
        File.readlines(opts.class).each do |line|
            line.chomp!
            if line == '==='
                puts
            elsif line[0] && line[0] != ?#
                puts "#{cnt[line].to_s.rjust(3, ' ')} #{line}"
            end
        end
    else
        lvls.each do |lvl|
            puts "#{lvl}:"
            $db.entries.each do |e|
                next unless e.lvl == lvl.downcase
                puts "#{cnt[e.formal]} #{e.formal}"
            end
        end
    end
end

if ARGV.include? 'summary'
    cnts = $lvl.map{|x|[x,0]}.to_h
    seqs.each do |seq|
        if (seq.tags & $lvl).size != 1
            puts 'bad sequence'
            totxt STDOUT, [seq], {mode: :prod}
            abort
        end
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

if ARGV.include? 'json'
    tojson STDOUT, seqs
end

if ARGV.include? 'debug'
    totxt STDOUT, seqs, {debug: true}
end

if ARGV.include? 'level'
    seqs.each do |seq|
        puts "#{seq.name} #{seq.tags*' '}"
        puts seq.calls.flat_map{|call|
            call.formal ? call.formal.split.map{|x| $db.lookup[x] ? $db.lookup[x].lvl : nil}.compact : []
        }.join ' '
    end
end

if ARGV.include? 'live'
    sidebar = []
    loop {
        lookup = {}
        tbl = seqs.map.with_index{|seq,i|
            lookup[k = i.to_s(26).tr('0-9a-z', 'a-z')] = seq
            [k, seq.calls.size.to_s, seq.name[0..40], seq.tags.join(' ')]
            [k, seq.calls.size.to_s, seq.name[0..40]]
        }.transpose.map{|arr|
            sz = arr.map(&:size).max
            arr.map{|x| x.ljust(sz+2, ' ') }
        }.transpose.map(&:join)

        tbl += [tbl.size == 0 ? '' : ' '*tbl[0].size] * (sidebar.size-tbl.size) if sidebar.size>tbl.size
        sidebar += [''] * (tbl.size-sidebar.size) if tbl.size>sidebar.size

        puts [tbl,sidebar].transpose.map{|x| x.join '   '}

        q = STDIN.gets
        break unless q
        if q = lookup[q.chomp]
            ss = StringIO.new
            q.totxt ss, {mode: :prod}
            sidebar = ss.string.split "\n"
            seqs.filter!{|seq| seq != q}
            File.open('livedone', ?a) do |livedone|
                livedone.puts q.date
            end
        else
            sidebar = []
        end

    }
end

File.open('cache', ?w) do |f| Marshal.dump $db.cache, f end if File.exists? 'cache'
