def to_type c
    case c
    when ?n then Number
    when ?r then Direction
    when ?d then Designator
    when ?f, "f'" then Formation
    when ?c then Entry
    end
end

class Constituent
    attr_accessor :val
    def initialize val; @val = val; end
    def formal; self.val; end
    def verbal; self.val; end
    def self.consume s
        self::Domain.each do |t|
            return [self.new(t), s[t.size+1..-1]] if s.downcase.start_with? t
        end
        return [nil, s]
    end
end

class Entry < Constituent

    attr_accessor :lvl, :match, :args, :sd, :formal, :verbal, :specs

    def initialize line
        @args = []
        @match = :exact

        @lvl, *words = line.split
        lower = words[-1] == 'LOWER'
        upper = words[-1] == 'UPPER'
        words.pop if lower || upper

        while to_type words[-1]
            @match = :prefix
            @args.unshift words.pop
        end

        while to_type words[0]
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

class Number < Constituent
    def self.consume s
        a, b = s.split ' ', 2
        a =~ /^[0-9]+(\/[0-9]+)?$/ ? [self.new(a), b] : [nil, s]
    end
end

class Direction < Constituent
    Domain = 'right|left|in|out|forward|backward'.split ?|
end

class Designator < Constituent
    Domain = 'boys|girls|leads|trailers|centers|ends|very centers|very ends|heads|sides'.split ?|
    def verbal; self.val.sub 'very', 'very '; end
end

class Formation < Constituent
    Domain = 'lines|waves|columns|diamonds|boxes'.split ?|
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
                # TODO concatenating lvl and sd gives wrong results after MATCH
                k, v = args.join(' ').split ' = '
                v ||= cur.lvl + ' ' + cur.sd
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
        return self.to_formal sd if type == ?c
        arg, s = to_type(type).consume sd
        !s || s == '' ? arg.formal : nil
    end

    def to_formal sd
        (@entries+@aliases).each do |e|
            case e.match
            when :exact
                return e.formal if sd == e.sd
            when :prefix
                [[' ', ''], [', ', ''], [' [', ']']].each do |s,t|
                    if sd.start_with?(e.sd + s) && sd.end_with?(t)
                        s = sd[e.sd.size+s.size..-1-t.size]
                        tlist = e.args.dup
                        alist = []
                        while tlist.size > 1
                            typ = to_type tlist.shift
                            arg, s = typ.consume s
                            alist.push(arg ? arg.formal : nil)
                        end
                        alist.push self.parse_arg(tlist[0], s)
                        return "#{e.formal} #{alist.join ' '}" if alist.all?{|x|x}
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

        # some special cases
        if sd.split(', ')[0] =~ /^\d+\/\d+$/
            frac = $&
            x = self.parse_arg ?c, sd[frac.size+2..-1]
            return "do #{frac} #{x}" if x
        end

        if sd =~ /^\(.*\) (\d+) TIMES$/
            frac = $1
            x = self.parse_arg ?c, sd[1..-9-frac.size]
            return "do #{frac} #{x}" if x
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
        if type == ?c
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
        t = to_type type
        return t ? Node.new(t.new head) : nil
    end

    def to_verbal formal
        return nil unless formal
        tree = self.read_token ?c, formal.split
        return nil unless tree
        tree.verbal
    end

end
