$types = 'nrdc'.chars

class Entry

    attr_accessor :match, :args, :sd, :formal, :verbal, :specs

    def initialize line
        @args = []
        @match = :exact

        lvl, *words = line.split

        while $types.include? words[-1]
            @match = :prefix
            @args.unshift words.pop
        end

        while $types.include? words[0]
            @match = :suffix
            @args.push words.shift
        end

        @sd = words.join(' ').gsub(?&, 'and')
        @sd.upcase! if @args == [?c]

        @formal = words.join.gsub(?-, '')
        @verbal = words.join ' '
        @verbal = @verbal + ' ' + @args.map.with_index{|_,i| "$#{i+1}"}.join(' ') if @match == :prefix
        @verbal = @args.map.with_index{|_,i| "$#{i+1}"}.join(' ') + ' ' + @verbal if @match == :suffix

        @specs = {}
    end

end

class Number
    attr_accessor :n
    def initialize n
        @n = n
    end
    def formal; self.n; end
    def verbal; self.n; end
    def specs; {}; end
end

class Direction
    Domain = 'right|left|in|out'.split ?|
    attr_accessor :r
    def initialize r
        @r = r
    end
    def formal; self.r; end
    def verbal; self.r; end
    def specs; {}; end
end

class Designator
    Domain = 'boys|girls|leads|trailers|centers|ends|very centers|very ends|heads|sides'.split ?|
    attr_accessor :d
    def initialize d
        @d = d
    end
    def formal; self.d; end
    def verbal; self.d.sub 'very', 'very '; end
    def specs; {}; end
end

class Node
    attr_accessor :head, :children
    def initialize head, children=[]
        @head = head
        @children = children
    end
    def verbal
        s = self.head.specs[self.children.map{|c| c.head.formal}.join ' ']
        return s if s
        return self.head.verbal.gsub(/\$(\d+)/) { self.children[$1.to_i-1].verbal }
    end
end

class Db

    def initialize fname

        @entries = []
        @aliases = []
        cur = nil
        File.open(fname).each_line do |line|
            line.chomp!
            next if line.empty?
            next if line[0] == ?#
            cmd, *args = line.split
            case cmd
            when 'ALIAS'
                src, dest = line.split ' = '
                cur = Entry.new src
                cur.formal = dest
                @aliases.push cur
            when 'MATCH'
                cur.match = args[0].to_sym
                cur.sd = args[1..-1].join ' ' if args.size > 1
            when 'OUT'
                cur.verbal = args.join ' '
            when 'SPEC'
                k, v = args.join(' ').split(' = ')
                cur.specs[k] = v
            else
                cur = Entry.new line
                @entries.push cur
            end
        end

        # some hardcoded content
        Designator::Domain.each do |d|
            a = Entry.new "ALIAS #{d} c"
            a.formal = "just #{d.gsub ' ', ''}"
            @aliases.push a
            a = Entry.new "ALIAS #{d} c"
            a.sd = d
            a.formal = "just #{d.gsub ' ', ''}"
            @aliases.push a
        end

        @lookup = {}
        @entries.each do |e|
            @lookup[e.formal] = e
        end

    end

    def parse_arg type, sd
        case type
        when ?n then
            return sd if sd =~ /^[0-9]+(\/[0-9]+)?$/
        when ?r then
            return sd if sd =~ /^(right|left|in|out)$/
        when ?d then
            return sd if sd =~ /^(boys|girls|leads|trailers|(very )?(centers|ends))$/
        when ?c then
            return self.to_formal sd
        end
        nil
    end

    def to_formal sd
        (@entries+@aliases).each do |e|
            case e.match
            when :exact
                return e.formal if sd == e.sd
            when :prefix
                if sd.start_with?(e.sd + ' ')
                    x = self.parse_arg e.args[0], sd[e.sd.size+1..-1]
                    return "#{e.formal} #{x}" if x
                end
            when :suffix
                if sd.end_with?(' ' + e.sd)
                    x = self.parse_arg e.args[0], sd[0...-(e.sd.size+1)]
                    return "#{e.formal} #{x}" if x
                end
            end
        end
        nil
    end

    def read_token type, tokens
        head = tokens.shift
        case type
        when ?n then
            return Node.new Number.new head
        when ?r then
            return Node.new Direction.new head
        when ?d then
            return Node.new Designator.new head
        when ?c then
            e = @lookup[head]
            return nil unless e
            args = []
            e.args.each do |a|
                t = self.read_token a, tokens
                return nil unless t
                args.push t
            end
            return Node.new e, args
        end
        nil
    end

    def to_verbal formal
        return nil unless formal
        tree = self.read_token ?c, formal.split
        return nil unless tree
        tree.verbal
    end

end
