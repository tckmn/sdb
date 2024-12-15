require 'json'
require 'open3'
require_relative 'db'

# TODO maybe this belongs somewhere else
$FILE = 'seqs'

$db = Db.new 'db'

# TODO what an ugly hack
$flag = ""

# TODO a ton of this might have to be more intelligent some day
# but this hodgepodge of special cases will do for now
def playback sd
    return nil if sd == 'comment'
    sd = sd.gsub(/{[^}]*}/, '').strip

    dpth = 0
    depths = sd.chars.each.map do |ch,idx|
        case ch
        when ?(, ?[ then dpth += 1; dpth-1
        when ?), ?] then dpth -= 1; dpth
        else dpth
        end
    end

    idx = ->pat,d,errok=false {
        res = sd.gsub(pat).map { $`.size }.select{|p| depths[p] == d }
        abort "error parsing #{sd}" unless res.size == 1 || errok
        errok == :mult ? res : res[0]
    }

    if sd[0] == ?( && sd[-1] == ?)
        if (pos = idx[/;/, 1, true])
            return "two calls in succession\n#{playback sd[1...pos]}\n#{playback sd[pos+1...-1]}"
        end
        # TODO
        return playback sd[1...-1]
    end

    if sd.start_with? 'CHECKPOINT '
        pos = idx[/ BY /, 0]
        return "checkpoint\n#{playback sd[11...pos]}\n#{playback sd[pos+4..-1]}"
    end

    if sd.start_with? 'REVERSE CHECKPOINT '
        pos = idx[/ BY /, 0]
        return "reverse checkpoint\n#{playback sd[19...pos]}\n#{playback sd[pos+4..-1]}"
    end

    if sd.start_with? 'INTERLACE '
        pos = idx[/ WITH /, 0]
        return "interlace\n#{playback sd[10...pos]}\n#{playback sd[pos+6..-1]}"
    end

    if sd.start_with? 'SANDWICH '
        pos = idx[/ AROUND /, 0]
        return "sandwich\n#{playback sd[9...pos]}\n#{playback sd[pos+8..-1]}"
    end

    # TODO bad
    if sd =~ /^DELAY: (.*) BUT (.*) WITH A \[(.*)\]$/
        one, three = $1, $3
        return "#{$2}\n#{playback one}\n#{playback three}"
    end

    # TODO bad
    if sd =~ /^((?:HALF|\d+\/\d+) AND (?:HALF|\d+\/\d+)) (.*) AND (.*)$/
        two, three = $2, $3
        return "#{$1}\n#{playback two}\n#{playback three}"
    end

    if sd.start_with? 'OWN THE '
        pos = idx[/ BY /, 0]
        head = sd[0...pos].split ?,, 2
        return "#{head[0]}\n#{playback head[1]}\n#{playback sd[pos+4..-1]}"
    end

    # TODO very bad
    if !sd.include?('first couple go') && !sd.include?('the windmill,') && !sd.include?('separate,') && !sd.include?('split the outsides,') && (!sd.include?('line of 6,') || sd.count(',')>1) && !sd.include?('line of 8,') && !sd.include?('first go') && !sd.include?('but on the') && !sd.include?('new centers to a wave') && !sd.include?('allemande thar,') && (pos = idx[/,/, 0, true])
        return "#{sd[0...pos]}\n#{playback sd[pos+1..-1]}"
    end

    if sd =~ /^\(?(.*?)\)? ((?:[^ ]+) TIMES|TWICE|1-\d+\/\d+)$/
        return "#{$2}\n#{playback $1}"
    end

    # TODO
    if sd.include? ?[
        sdmod = sd+''
        pairs = idx[/\[/, 0, :mult].zip idx[/\]/, 0, :mult]
        pairs.reverse.each do |a,b|
            sdmod[a..b] = '<anything>'
        end
        return ([sdmod] + pairs.map{|a,b| playback sd[a+1..b-1]}).join ?\n
    end

    return sd # tried our best
end

class Call
    attr_writer :formal, :verbal

    def initialize sd
        @sd = sd
        @formal = nil
        @verbal = nil
        if true
            @cf = $db.to_formal(@sd, :ENTRY)
            @cv = $db.to_verbal(self.formal)
        end
    end

    def sd; @sd; end
    def formal; @formal || @cf || (@cf = $db.to_formal(@sd, :ENTRY)); end
    def verbal; @verbal || @cv || (@cv = $db.to_verbal(self.formal)); end

    def totxt f, opts
        if opts[:mode] == :prod
            prod = self.prod
            f.puts prod.gsub(/^/, '    ') if prod
        elsif opts[:mode] == :playback
            playback = playback @sd
            f.puts playback.gsub(/^/, '    ') if playback
        else
            if @sd == 'comment'
                f.puts "!#{self.verbal}"
            else
                f.puts @sd
                if !self.formal && !self.verbal
                    f.puts "%%% formal"
                elsif !self.verbal
                    f.puts "%%% verbal"
                else
                    f.puts "=#{self.formal}" if @formal || opts[:debug]
                    f.puts "\"#{self.verbal}\"" if @verbal || opts[:debug]
                end
            end
        end
    end

    def tojson
        self.prod
    end

    def prod
        ret = nil
        if @sd == 'comment' && @verbal == 'hard'
            $flag = '*** '
        elsif @sd == 'comment' && @verbal == 'fast'
            $flag = '    '
        elsif @sd == 'comment' && @verbal.start_with?('form ')
            ret = @verbal[5..-1].gsub('\n', "\n")
        elsif self.verbal == ?^
            #nop
        else
            ret = "#{$flag}#{self.verbal || @sd}"
            $flag = ''
        end
        ret
    end
end

class Sequence
    attr_accessor :periphery, :date, :tags, :name, :calls

    def initialize periphery, date, tags, name=nil, calls=[]
        @periphery = periphery
        @date = date
        @tags = tags
        @name = name
        @calls = calls
    end

    def totxt f, opts
        f.puts "* #{@periphery} #{@date} #{@tags.join ' '}"
        f.puts @name
        # TODO
        if opts[:mode] == :prod
            t = self.timing
            f.puts "timing: #{t}" if t
        end
        f.puts
        f.puts('    ' + {
            ?H => 'heads start',
            ?S => 'sides start',
            ?J => 'just as they are'
        }[@periphery[0]]) if opts[:mode] == :playback
        calls.each do |c| c.totxt f, opts end
        f.puts('    ' + self.resolve) if opts[:mode] == :prod
        f.puts
    end

    def tojson
        # TODO uglyyy
        if true

        STDERR.puts "playback #{@date}"
        calls = Open3.popen2 '/home/tckmn/misc/sd/playbacksdcli', 'c4', :chdir => '/home/tckmn/misc/sd' do |stdin, stdout, thr|
            nil while stdout.gets.chomp != '##INPUT READY##'
            stdin.puts({
                ?H => 'heads start',
                ?S => 'sides start',
                ?J => 'just as they are'
            }[@periphery[0]])
            nil while stdout.gets.chomp != '##INPUT READY##'
            prevsetup = []
            @calls.map do |call|
                setup = []
                if !@tags.include?('noplayback') && pb = playback(call.sd)
                    stdin.puts pb
                    looking = false
                    (pb.chomp.count("\n")+1).times do
                        while line = stdout.gets.chomp
                            looking = false if line == '##SETUP END##'
                            setup.push line if looking
                            looking = true if line == '##SETUP START##'
                            break if line == '##INPUT READY##'
                        end
                    end
                end
                if cj = call.tojson
                    [cj, (setup.empty? ? prevsetup : (prevsetup=setup))]
                elsif call.verbal == ?^
                    prevsetup.clear.concat setup
                    nil
                end
            end.compact
        end

        else

            calls = @calls.map{|call| v = call.tojson; v ? [v, ['']] : nil}.compact

        end

        {
            periphery: @periphery,
            date: @date,
            tags: @tags,
            name: @name,
            calls: calls + [[resolve, ['', 'resolved!', '']]]
        }
    end

    def resolve
        {
            ?N => 'at home',
            ?C => 'circle home',
            ?R => 'right and left grand',
            ?M => 'mini-grand',
            ?L => 'left allemande',
            ?P => 'promenade',
            ?E => 'reverse promenade',
            ?S => 'single file promenade',
            ?F => 'reverse single file promenade',
            ?D => 'dixie grand, left allemande',
            ?W => 'swing and promenade',
            ?- => 'NOT RESOLVED'
        }[@periphery[1]] + "  (#{@periphery[2]}/8 promenade)"
    end

    def timing
        @calls.sum{|c| $db.to_timing(c.formal) } rescue nil
    end
end

def fromtxt f
    seqs = []
    cur = nil
    call = nil
    f.each_line do |line|
        line.chomp!
        case line[0]
        when nil then nil
        when ?% then nil
        when ?!
            comm = Call.new 'comment'
            comm.verbal = line[1..-1]
            cur.calls.push comm
        when ?*
            parts = line[2..-1].split
            cur = Sequence.new parts[0], parts[1..2].join(' '), parts[3..-1]
            seqs.push cur
        when ?=
            call.formal = line[1..-1]
        when ?"
            call.verbal = line[1..-2]
        else
            if cur.name.nil?
                cur.name = line
            else
                call = Call.new line
                cur.calls.push call
            end
        end
    end
    seqs
end

def totxt f, seqs, opts
    seqs.each do |seq|
        seq.totxt f, opts
    end
end

def tojson f, seqs
    f.puts JSON.generate seqs.map(&:tojson)
end
