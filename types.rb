require 'json'
require_relative 'db'

$db = Db.new 'db'
$lvl = ['ms', 'plus', 'a1', 'a2', 'c1', 'c2', 'c3a', 'c3b', 'c4', 'all']

# TODO what an ugly hack
$flag = ""

class Call
    attr_writer :formal, :verbal

    def initialize sd
        @sd = sd
        @formal = nil
        @verbal = nil
        if true
            @cf = $db.to_formal(@sd)
            @cv = $db.to_verbal(self.formal)
        end
    end

    def sd; @sd; end
    def formal; @formal || @cf || (@cf = $db.to_formal(@sd)); end
    def verbal; @verbal || @cv || (@cv = $db.to_verbal(self.formal)); end

    def totxt f, opts
        if opts[:mode] == :prod
            prod = self.prod
            f.puts prod.gsub(/^/, '    ') if prod
        else
            if @sd == 'comment'
                f.puts "!#{self.verbal[1..-2]}"
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
        if @sd == 'comment' && @verbal == '"hard"'
            $flag = '*** '
        elsif @sd == 'comment' && @verbal.start_with?('"form ')
            ret = @verbal[6..-2].gsub('\n', "\n")
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
        f.puts
        calls.each do |c| c.totxt f, opts end
        f.puts('    ' + self.resolve) if opts[:mode] == :prod
        f.puts
    end

    def tojson
        {
            periphery: @periphery,
            date: @date,
            tags: @tags,
            name: @name,
            calls: @calls.map(&:tojson).compact + [resolve]
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
            ?D => 'dixie grand, left allemande',
            ?- => 'NOT RESOLVED'
        }[@periphery[1]] + "  (#{@periphery[2]}/8 promenade)"
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
            comm.verbal = ?" + line[1..-1] + ?"
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
