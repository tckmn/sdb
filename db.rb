$types = 'nrdc'.chars

class Entry

    attr_accessor :lvl, :match, :args, :sd, :formal, :verbal, :specs

    def initialize line
        @args = []
        @match = :exact

        @lvl, *words = line.split
        lower = words[-1] == 'LOWER'
        upper = words[-1] == 'UPPER'
        words.pop if lower || upper

        while $types.include? words[-1]
            @match = :prefix
            @args.unshift words.pop
        end

        while $types.include? words[0]
            @match = :suffix
            @args.push words.shift
        end

        @sd = words.join(' ').gsub(?&, 'and')
        @sd.upcase! if upper || (@args == [?c] && @match == :prefix && !lower)

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
end

class Direction
    Domain = 'right|left|in|out'.split ?|
    attr_accessor :r
    def initialize r
        @r = r
    end
    def formal; self.r; end
    def verbal; self.r; end
end

class Designator
    Domain = 'boys|girls|leads|trailers|centers|ends|very centers|very ends|heads|sides'.split ?|
    attr_accessor :d
    def initialize d
        @d = d
    end
    def formal; self.d; end
    def verbal; self.d.sub 'very', 'very '; end
end

class Node
    attr_accessor :head, :children
    def initialize head, children=[]
        @head = head
        @children = children
    end
    def verbal
        # TODO this sucks lmao
        if self.children.size > 0
            arr = self.children.map{|c| c.head.formal}
            (1..self.children.size).each do |i|
                arr = self.children.map{|c| c.head.formal}
                s = self.head.specs[arr[0...i].join ' ']
                return s.verbal.gsub(/\$(\d+)/) { self.children[$1.to_i-1+i].verbal } if s
            end
        end
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
                k, v = args.include?(?=) ? args.join(' ').split(' = ') : [args.join(' '), cur.lvl+' '+cur.sd]
                cur.specs[k] = Entry.new v
                a = Entry.new v
                a.formal = "#{cur.formal} #{k}"
                @aliases.push a
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
            return sd if sd =~ /^(right|left|in|out|forward|backward)$/
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
                [[' ', ''], [', ', ''], [' [', ']']].each do |s,t|
                    if sd.start_with?(e.sd + s) && sd.end_with?(t)
                        x = self.parse_arg e.args[0], sd[e.sd.size+s.size..-1-t.size]
                        return "#{e.formal} #{x}" if x
                    end
                end
            when :suffix
                [['', ' '], ['[', '] ']].each do |s,t|
                    if sd.end_with?(t + e.sd)
                        x = self.parse_arg e.args[0], sd[s.size...-e.sd.size-t.size]
                        return "#{e.formal} #{x}" if x
                    end
                end
            end
        end
        nil
        # if m = Regexp.new('^' + e.sd.gsub(/\$(\d+)/, '(?<a\1>.+)') + '$').match(sd)
        #     args = [e.formal]
        #     e.args.each.with_index do |a,i|
        #         x = self.parse_arg e, m["a#{i+1}"]
        #         return nil unless x
        #         args.push x
        #     end
        #     return args.join ' '
        # end
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
