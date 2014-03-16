require 'order_query/order_space'
module OrderQuery

  class RelativeOrder
    attr_reader :scope, :order, :values, :options

    def initialize(record, scope, order)
      @scope  = scope
      @order  = order.is_a?(OrderSpace) ? order : OrderSpace.new(scope, order)
      @values = Hash.new { |h, key|
        h[key] = record.send(key)
      }
    end

    def first_item
      order.scope.first
    end

    def last_item
      order.scope.last
    end

    def count
      @total ||= scope.count
    end

    def position
      count - items_after.count
    end

    def next_item(loop = true)
      items_after.first || (first_item if loop)
    end

    def prev_item(loop = true)
      items_before.first || (last_item if loop)
    end

    def items_after
      items :after
    end

    def items_before
      items :before
    end

    def items(mode)
      scope             = (mode == :after ? order.scope : order.reverse_scope)
      query, query_args = build_query(mode)

      if query
        scope.where(query, *query_args)
      else
        scope
      end
    end

    protected

    # @param [:before or :after] mode
    def build_query(mode)
      # The next element will be the first one among elements with lesser order
      build_query_factor(
          order.map { |o| filter_attr(o, mode, false) },
          order.map { |o| filter_attr(o, mode, true) }
      )
    end

    # @param [Array] x query conditions
    # @param [Array] y query conditions
    # @return [query, query_args] The resulting query is as follows:
    #   x0 | y0 &
    #      (x1 | y1 &
    #        (x2 | y2 &
    #          (x3 | y3 & ... )))
    #
    # Explanation:
    #
    #   To narrow the result to only the records that come before / after the current one, build_query passes
    #   the values of x and y so that:
    #
    #   x matches order criteria with values that come after the current record.
    #   y matches order criteria with values equal to the current record's value, for resolving ties.
    #
    def build_query_factor(x, y, i = 0, n = x.length)
      q = []

      x_cond = [x[i][0].presence, x[i][1]]
      q << x_cond if x_cond[0]

      if i >= 1
        q << ['AND'] << y[i - 1]
      end

      if i < n - 1
        q << ['OR'] if x_cond[0]
        nested = build_query_factor(x, y, i + 1)
        q << ["(#{nested[0]})", nested[1]]
      end

      [q.map { |e| e[0] }.join(' '),
       q.map { |e| e[1] }.compact.reduce(:+) || []]
    end

    EMPTY_FILTER = ['', []]

    def filter_attr(spec, mode, eq = false)
      attr, attr_ord = spec.name, spec.order
      value          = values[attr]
      if attr_ord.is_a?(Array)
        attr_eq = "#{spec.col_name_sql} = ?"
        if eq
          [attr_eq, [value]]
        else
          # all up to current
          pos = attr_ord.index(value)
          # if current not in result set, do not apply filter
          return EMPTY_FILTER unless pos
          values = mode == :after ? attr_ord.from(pos + 1) : attr_ord.first(pos)
          return EMPTY_FILTER unless values.present?
          ["#{spec.col_name_sql} IN (?)", [values]]
        end
      else
        if eq
          op = '='
        else
          op = attr_ord == :asc ? '>' : '<' if mode == :after
          op = attr_ord == :asc ? '<' : '>' if mode == :before
        end
        ["#{spec.col_name_sql} #{op} ?", [value]]
      end
    end
  end
end
