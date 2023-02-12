$types = 'nrdc'.chars

class Entry

    attr_accessor :match, :out, :args, :sd, :formal, :verbal, :specs

    def initialize line
        @args = []
        @match = :exact
        @out = :exact

        lvl, *words = line.split

        while $types.include? words[-1]
            @match = :prefix
            @out = :prefix
            @args.unshift words.pop
        end

        while $types.include? words[0]
            @match = :suffix
            @out = :suffix
            @args.push words.shift
        end

        @sd = words.join(' ').gsub(?&, 'and')
        @sd.upcase! if @args == [?c]
        @formal = words.join.gsub(?-, '')
        @verbal = words.join ' '
        @specs = {}
    end

end

class Number
    attr_accessor :n
    def initialize n
        @n = n
    end
    def out; :exact; end
    def formal; self.n; end
    def verbal; self.n; end
end

class Direction
    attr_accessor :r
    def initialize r
        @r = r
    end
    def out; :exact; end
    def formal; self.r; end
    def verbal; self.r; end
end

class Designator
    attr_accessor :d
    def initialize d
        @d = d
    end
    def out; :exact; end
    def formal; self.d; end
    def verbal; self.d; end
end

class Node
    attr_accessor :head, :children
    def initialize head, children=[]
        @head = head
        @children = children
    end
    def verbal
        case self.head.out
        when :exact
            return self.head.verbal
        when :prefix
            s = self.head.specs[self.children[0].head.formal]
            return s if s
            return "#{self.head.verbal} #{self.children[0].verbal}"
        when :suffix
            s = self.head.specs[self.children[0].head.formal]
            return s if s
            return "#{self.children[0].verbal} #{self.head.verbal}"
        when :groups
            s = self.head.specs[self.children[0].head.formal]
            return s if s
            return self.head.verbal.gsub(/\$(\d+)/) { self.children[$1.to_i-1].verbal }
        end
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
                cur.out = args[0].to_sym
                cur.verbal = args[1..-1].join ' ' if args.size > 1
            when 'SPEC'
                k, v = args.join(' ').split(' = ')
                cur.specs[k] = v
            else
                cur = Entry.new line
                @entries.push cur
            end
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
