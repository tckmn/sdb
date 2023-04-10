require_relative 'db'

$db = Db.new 'db'
$lvl = ['MS', 'Plus', 'A1', 'A2', 'C1', 'C2', 'C3A', 'C3B', 'C4', 'all']

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
        f.puts @sd
        if !self.formal
            f.puts "%%% formal"
        elsif !self.verbal
            f.puts "%%% verbal"
        else
            f.puts "=#{self.formal}" if @formal || DEBUG
            f.puts "\"#{self.verbal}\"" if @verbal || DEBUG
        end
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
        unless BETTER
            f.puts('    ' + {
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
            }[@periphery[1]] + "  (#{@periphery[2]}/8 promenade)")
        end
        f.puts
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
