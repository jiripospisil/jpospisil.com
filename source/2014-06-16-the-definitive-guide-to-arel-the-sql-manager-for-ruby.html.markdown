---
title: The definitive guide to Arel, the SQL manager for Ruby
date: 2014-06-16 16:29 UTC
tags: ruby, arel
author: Jiri Pospisil
---
Arel is the kind of library that many of us Rails developers use on a daily
basis and might not even know about it. So what's this library whose name only
pops up when everything else fails all about?

It's all about providing frameworks with a way of building and representing SQL
queries. It's not the kind of library you would *typically* want to use directly
(although you could as shown in a minute). Arel is meant to be the basic
building block upon which frameworks build their own APIs that are more suitable
for the end user.

One of those frameworks is ActiveRecord (AR), the default ORM in Rails.
ActiveRecord's responsibility is to provide a connection to the database, a
convenient way to specify relationships between your models, provide a nice
query interface and all the other things we enjoy.

READMORE

```ruby
# ActiveRecord
User.first.comments.where(created_at: 2.days.ago..Time.current).limit(5)
```

Behind the scenes, ActiveRecord uses Arel to build the queries and ultimately
calls out to it to get the final SQL before shipping it to the database of your
choice.

So how exactly Arel achieves building the queries in such a flexible way? By
building an [AST](http://en.wikipedia.org/wiki/Abstract_syntax_tree). Arel
internally operates on AST nodes - you modify the query via a method call, Arel
modifies or creates the appropriate node in the tree.

<div class="image">
<img src="/images/arel/ast.png" width="347px" height="159px" title="An select query represented via AST" />
</div>

This kind of representation holds two important properties. First,
composability. By being composable you gain the power to build the query
iteratively, piece by piece, and even combine several queries together.  Many
parts of the API (and consequently AR's API) would be impossible or at least
very difficult handle without this property.

```ruby
# ActiveRecord

bob = User.where(email: "bob@test.com").where(active: true)
# => SELECT "users".* FROM "users" WHERE "users"."email" = 'bob@test.com' AND "users"."active" = 't'

details = User.select(:id, :email, :first_name).order(id: :desc)
# => SELECT "users"."id", "users"."email", "users"."first_name" FROM "users" ORDER BY "users"."id" DESC

bob.merge(details).first
# => SELECT "users"."id", "users"."email", "users"."first_name" FROM "users"
#    WHERE "users"."email" = 'bob@test.com' AND "users"."active" = 't'
#    ORDER BY "users"."id" DESC LIMIT 1
```

While a contrived example, it is sufficient to show that it'd be very difficult
to work with these queries without some sort of abstract representation.

The other equally important property is the completely obliviousness to the
outside world. Arel doesn't care what's going to happen with the result. It
might end up converted into a SQL query or into an entirely different format. In
fact, Arel is able to convert the query into the Graphviz's dot format and you
can create pretty diagrams out of it (more on that later).

<div class="image">
<img src="/images/arel/arel_to_formats.png" width="356px" height="96px" title="Arel converted to other formats" />
</div>

So far we've seen only [ActiveRecord's query
interface](http://guides.rubyonrails.org/active_record_querying.html), the part
built on top of Arel. Let's get below the surface and start working with Arel
directly. To play along, use the following instructions. The script will
download the correct version of libraries and leave you inside a Pry REPL
instance (run `bundle console` if you've left the REPL and want to come back). It's
always a good idea to inspect all 3rd party scripts before you run them.

```bash
cd /tmp
mkdir arel_playground && cd arel_playground

wget http://jpospisil.com/arel_setup.sh
# or
curl -L -o arel_setup.sh http://jpospisil.com/arel_setup.sh

bash ./arel_setup.sh
```

To stay current for the foreseeable future, the text is based on soon-to-be
released version of Arel. The text also contains a lot of links to the actual
Arel's source code, you are strongly encouraged to look around the file beyond
the highlighted area to see all of the options!

## Diving in with SelectManager

Let's start by building a select query that will give us all users. First, we
need to create an object representing the table itself. Notice that you can name
the table whatever you want, it doesn't have to exist anywhere.

```ruby
users = Arel::Table.new(:users)
```

`Arel::Table` itself doesn't do much but it has [a lot of handy
methods](https://github.com/rails/arel/blob/f50de54/lib/arel/table.rb#L45-L97)
which are responsible for delegating the calls deeper into the system. The
method we are interested in now is the
[project](https://github.com/rails/arel/blob/f50de54/lib/arel/table.rb#L83-85)
method. The name comes from [relational
algebra](http://en.wikipedia.org/wiki/Projection_(relational_algebra)) but rest
assured, it's just a plain `select`.

```ruby
select_manager = users.project(Arel.star)
```

Notice the use of
[Arel.star](https://github.com/rails/arel/blob/f50de54/lib/arel.rb#L30-32), a
convenience method for the `*` character. What we got back is an instance of
[Arel::SelectManager](https://github.com/rails/arel/blob/f50de54/lib/arel/select_manager.rb),
the object responsible for assembling of the select query. Now we should be able
to get the resulting SQL from `select_manager`.

```ruby
select_manager.to_sql
# => NoMethodError: undefined method `connection' for nil:NilClass
```

And it didn't work. If you think about it, the failure kind of makes sense
(although the error should be handled more gracefully) because we didn't
specified any database details and Arel has no way of knowing for what database
we want the query generated. Databases may differ in syntax, capabilities and
even in character escaping. Let's get ourselves an ActiveRecord database
connection and try again.

```ruby
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

users          = Arel::Table.new(:users, ActiveRecord::Base)
select_manager = users.project(Arel.star)

select_manager.to_sql
# => SELECT * FROM "users"
```

Notice we passed `ActiveRecord::Base` to the `Arel::Table`'s constructor. We
could have also set it globally via `Arel::Table.engine=`. With all that in
place, we finally have our precious SQL query.

The interesting thing is the collaboration between Arel and ActiveRecord. Arel
is technically independent from ActiveRecord but it needs to get the database
details from somewhere and currently it uses ActiveRecord. More specifically,
Arel requires ActiveRecord's APIs. There's even a fake ActiveRecord
implementation,
[FakeRecord](https://github.com/rails/arel/blob/f50de54/test/support/fake_record.rb),
that is [used](https://github.com/rails/arel/blob/f50de54/test/helper.rb#L6-L7) to
run the Arel's tests. In the past you needed a running MySQL server.

## Getting picky

Querying for all users' details is nice but let's be more specific. Say we
want to select only the users' ids and names. The key abstraction Arel provides
for working with attributes (column names) is
  [Arel::Attribute](https://github.com/rails/arel/blob/f50de54/lib/arel/attributes/attribute.rb).

 `Arel::Attribute` represents a single column of an arbitrary name. The easiest way
 to get a hold of an `Arel::Attribute` for a table is to use the
 [Arel::Table#[]](https://github.com/rails/arel/blob/f50de54/lib/arel/table.rb#L99-101)
 method. We can use the result right away in the `project` method.

```ruby
select_manager = users.project(users[:id], users[:name])
select_manager.to_sql
# => SELECT "users"."id", "users"."name" FROM "users
```

As you've probably noticed, the class gets included with a bunch of modules
which add a lot of functionality. The first module,
[Arel::Expressions](https://github.com/rails/arel/blob/f50de54/lib/arel/expressions.rb),
adds the common aggregate functions.

```ruby
select_manager = users.project(users[:comments_count].average)
select_manager.to_sql
# => SELECT AVG("users"."comments_count") AS avg_id FROM "users"
```

The results of these aggregate functions are kept in variables with hardcoded
names (`avg_id` in this case). Fortunately,
[Arel::AliasPredication](https://github.com/rails/arel/blob/f50de54/lib/arel/alias_predication.rb) comes to our rescue.


```ruby
select_manager = users.project(users[:vip].as("status"), users[:vip].count.as("count")).group("vip")
select_manager.to_sql
# => SELECT "users"."vip" AS status, COUNT("users"."vip") AS count FROM "users"  GROUP BY vip
```

The [Arel::Math](https://github.com/rails/arel/blob/f50de54/lib/arel/math.rb)
module is pretty neat. It implements the common math operators so that we can
use them directly on the attributes as if we're working with the values.

```ruby
select_manager = users.project((users[:stared_comments_count] / users[:comments_count]).as("ratio"))
select_manager.to_sql
# => SELECT "users"."stared_comments_count" / "users"."comments_count" AS ratio FROM "users"
```

## Extending our index finger

Select queries which return data from the whole table are quite rare, usually
you want to have more fine grained control. Let's see how Arel handles these
cases. The starting point is again
[Arel::Attribute](https://github.com/rails/arel/blob/f50de54/lib/arel/attributes/attribute.rb).
More specifically, it's one of its included modules,
[Arel::Predications](https://github.com/rails/arel/blob/f50de54/lib/arel/predications.rb).
By looking at the code you can see a lot of handy methods, many of which do not
have their equivalent in ActiveRecord' APIs.

```ruby
select_manager = users.project(Arel.star).where(users[:id].eq(23).or(users[:id].eq(42)))
select_manager = users.project(Arel.star).where(users[:id].eq_any([23, 42]))
select_manager.to_sql
# => SELECT * FROM "users"  WHERE ("users"."id" = 23 OR "users"."id" = 42)
```

For more complicated queries, it's usually best to the build the parts
individually and combine them together at the end.

```ruby
admins_vips    = users[:admin].eq(true).or(users[:vip].eq(true))
with_karma     = users[:karma].gteq(5000).and(users[:hellbanned].eq(false))

select_manager = users.project(users[:id]).where(admins_vips.or(with_karma)).order(users[:id].desc)
select_manager.to_sql
# => SELECT COUNT("users"."id") FROM "users" WHERE (("users"."admin" = 't' OR "users"."vip" = 't')
#      OR "users"."karma" >= 5000 AND "users"."hellbanned" = 'f')
#    ORDER BY "users"."id" DESC
```

## The more the merrier

Next, let's take a look at join statements. In line with the previously shown
API, Arel [exposes
joins](https://github.com/rails/arel/blob/f50de54/lib/arel/select_manager.rb#L104-119)
directly from `Arel::SelectManager`.  As expected, Arel supports the usual
`INNER JOIN`, and `LEFT`, `RIGHT`, `FULL` `OUTER JOIN` kinds.

```ruby
comments       = Arel::Table.new(:comments, ActiveRecord::Base)

select_manager = users.project(Arel.star).join(comments).on(users[:id].eq(comments[:user_id]))
select_manager.to_sql
# => SELECT * FROM "users" INNER JOIN "comments" ON "users"."id" = "comments"."user_id"
```

To create the remaining kinds of joins, we need to explicitly pass a second
argument to the `join` method.

```ruby
select_manager = users.project(Arel.star).join(comments, Arel::Nodes::OuterJoin).
  on(users[:id].eq(comments[:user_id])).
  having(comments[:id].count.lteq(16)).
  take(15)

select_manager.to_sql
# => SELECT * FROM "users" LEFT OUTER JOIN "comments" ON "users"."id" = "comments"."user_id"
#    HAVING COUNT("comments"."id") <= 16 LIMIT 15
```

Since the need for `OuterJoin` is very common, there's a shortcut called
[outer_join](https://github.com/rails/arel/blob/f50de54/lib/arel/select_manager.rb#L117-119), which internally calls the `join` method with the
`Arel::Nodes::OuterJoin` argument for us. To get the remaining kinds of joins,
there are `Arel::Nodes::FullOuterJoin` and `Arel::Nodes::RightOuterJoin` nodes
available.

The rarely used `CROSS JOIN` kind is not directly supported. What's also not
supported out of the box is the `USING` clause but as with the previous case, we
can get around that by resorting to creating `Arel::Nodes::SqlLiteral` manually
or better yet by rewriting the query to use the supported constructs.

## There's always more

Arel comes with support even for slightly advanced features such as `WITH`
statements or `WINDOW` functions. Let's try to replicate an example [7.8.1.
SELECT in WITH](http://www.postgresql.org/docs/9.3/static/queries-with.html)
from the PostgreSQL manual. The query is quite complicated, it consists of 2
`WITH` statements and a few subqueries. Let's focus first on the `WITH`
clauses `regional_sales` and `top_regions`.

```ruby
orders          = Arel::Table.new(:orders, ActiveRecord::Base)
reg_sales       = Arel::Table.new(:regional_sales, ActiveRecord::Base)
top_regions     = Arel::Table.new(:top_regions, ActiveRecord::Base)

reg_sales_query = orders.project(orders[:region], orders[:amount].sum.as("total_sales")).
                    group(orders[:region])
reg_sales_as    = Arel::Nodes::As.new(reg_sales, reg_sales_query)
```

Nothing we haven't seen before. The only exception is the explicit instantiation
of `Arel::Nodes::As`. There doesn't seem to be a way around it as you cannot
create an alias via the usual `as` method.

```ruby
top_regions_subquery = reg_sales.project(Arel.sql("SUM(total_sales) / 10"))
top_regions_query    = reg_sales.project(reg_sales[:region]).
                        where(reg_sales[:total_sales].gt(top_regions_subquery))
top_regions_as       = Arel::Nodes::As.new(top_regions, top_regions_query)
```

The use of
[Arel.sql](https://github.com/rails/arel/blob/f50de54/lib/arel.rb#L26-L28) is
not ideal, however, as with the previous part, there is not a way to use math
operations on the result of the `sum` call.

```ruby
attributes = [orders[:region], orders[:product], orders[:quantity].as("product_units"),
               orders[:amount].as("product_sales")]

res = orders.project(*attributes).where(orders[:region].in(top_regions.project(top_regions[:region]))).
        with([reg_sales_as, top_regions_as]).group(orders[:region], orders[:product])

res.to_sql
```

With all of that in place, we have our final query. If we look at the parts
individually, they are pretty simple. Overall, however, the code is longer than
a pure SQL solution. The fact doesn't matter when using Arel pragmatically but
if composed by hand, one has to always consider whether it's actually worth the
  effort.

## SelectManager is not the only one

So far all we've been doing was writing select queries via `SelectManager`, but
Arel of course supports the other operations as well. Let's quickly take a look
at deleting. There are two ways you can create a delete query. The first way is
to explicitly instantiate
[Arel::DeleteManager](https://github.com/rails/arel/blob/f50de54/lib/arel/delete_manager.rb).

```ruby
delete_manager = Arel::DeleteManager.new(ActiveRecord::Base)
delete_manager.from(users).where(users[:id].eq_any([4, 8]))
delete_manager.to_sql
# => DELETE FROM "users" WHERE ("users"."id" = 4 OR "users"."id" = 8)
```

The other way, although it seems deprecated, is to create the delete statement
from a select statement by calling
[compile_delete](https://github.com/rails/arel/blob/f50de54/lib/arel/crud.rb#L32-37)
(there are similar methods for the other operations as well).  By looking at the
code we can see that all it does is pick values out of the object it's mixed
into (`Arel::SelectManager`) and passing it to a new instance of
`Arel::DeleteManager`.

```ruby
select_manager = users.project(users[:id], users[:name]).where(users[:banned].eq(true))
select_manager.to_sql
# => SELECT "users"."id", "users"."name" FROM "users"  WHERE "users"."banned = 't'

delete_manager = select_manager.compile_delete
delete_manager.to_sql
# => DELETE FROM "users" WHERE "users"."banned" = 't'
```

The managers for the remaining operations,
[InsertManager](https://github.com/rails/arel/blob/f50de54/lib/arel/insert_manager.rb)
and
[UpdateManager](https://github.com/rails/arel/blob/f50de54/lib/arel/update_manager.rb),
work in a similar fashion.

```ruby
insert_manager = Arel::InsertManager.new(ActiveRecord::Base)
insert_manager.insert([[users[:name], "Bob"], [users[:admin], true]])
insert_manager.to_sql
# => INSERT INTO "users" ("name", "admin) VALUES ('Bob', 't')
```

Notice that `Arel::InsertManager` is able to figure out the name of the table
we're inserting to automatically through the use of `Arel::Attribute`. If we're to
use string literals instead, we'd have to specify the table name via the
[into](https://github.com/rails/arel/blob/f50de54/lib/arel/insert_manager.rb#L8-11)
method. The same is not offered in `Arel::UpdateManager` and we have to use
[table](https://github.com/rails/arel/blob/f50de54/lib/arel/update_manager.rb#L29-32).

```ruby
update_manager = Arel::UpdateManager.new(ActiveRecord::Base)
update_manager.table(users).where(users[:id].eq(42))
update_manager.set([[users[:name], "Bob"], [users[:admin], true]])
update_manager.to_sql
# => UPDATE "users" SET "name" = 'Bob', "admin" = 't' WHERE "users"."id" = 42
```

## The story of `.to_sql`

Throughout the article we've been calling `.to_sql` in almost every example and
never actually talked about how it works. As mentioned in the beginning, Arel
internally represents all queries as nodes in an abstract syntax tree. The
managers create and modify these trees. Naturally, something later has to take
the resulting tree and process it to the final output. Arel uses various kinds
of visitors to accomplish this (see the [Visitor
pattern](http://en.wikipedia.org/wiki/Visitor_pattern)).

In essence, the visitor pattern abstracts away how the nodes of an AST are
processed from the nodes themselves. The nodes stay the same, yet it's possible
to apply different visitors and get different results. This is exactly what Arel
needs to generate all those kinds of output formats.

The Arel's implementation of the visitor pattern is interesting. It uses a
variation called [Extrinsic
Visitor](http://web.info.uvt.ro/~oaritoni/inginerie/Cursuri/DesignPatterns/L7/Visitor/nordberg.ps.pdf).
The variation takes great advantage of Ruby's dynamic behavior and the
information available at runtime. Instead of forcing the nodes to implement the
`accept` method, the visitor calls
[accept](https://github.com/rails/arel/blob/f50de54/lib/arel/visitors/visitor.rb#L4-6)
on itself with the root node as argument. It then inspects the node to find out
its type and
[looks](https://github.com/rails/arel/blob/f50de54/lib/arel/visitors/visitor.rb#L21-31)
the appropriate visit method. To make the dispatching part faster, the code uses
a simple [hash
table](https://github.com/rails/arel/blob/f50de54/lib/arel/visitors/visitor.rb#L10-L15)
for caching purposes.

```ruby
{
  Arel::Visitors::SQLite => {
    Arel::Nodes::SelectStatement => "visit_Arel_Nodes_SelectStatement",
    Arel::Nodes::SqlLiteral      => "visit_Arel_Nodes_SqlLiteral",
    Arel::Nodes::Or              => "visit_Arel_Nodes_Or",
    Arel::Attributes::Attribute  => "visit_Arel_Attributes_Attribute",
    Arel::Nodes::InnerJoin       => "visit_Arel_Nodes_InnerJoin",
    Arel::Nodes::Having          => "visit_Arel_Nodes_Having",
    Arel::Nodes::Limit           => "visit_Arel_Nodes_Limit"
    Fixnum                       => "visit_Fixnum",
  }
}
```

If we look into the [visitors
directory](https://github.com/rails/arel/tree/f50de54/lib/arel/visitors), we can
see a few visitors that Arel comes with by default. Some of them directly
correspond to a particular database, some are used only internally and some are
used only from AR. Notice that all database related visitors inherit from the
[to_sql](https://github.com/rails/arel/blob/f50de54/lib/arel/visitors/to_sql.rb)
visitor, which is doing most of the work, and that the particular database
visitor handles only the differences specific to the concrete database. Let's
create a select manager and get the SQL query out of it without the `to_sql`
method.

```ruby
select_manager = users.project(Arel.star)
select_manager.to_sql
# => SELECT * FROM "users"

sqlite_visitor = Arel::Visitors::SQLite.new(ActiveRecord::Base.connection)
collector      = Arel::Collectors::SQLString.new
collector      = sqlite_visitor.accept(select_manager.ast, collector)
collector.value
# => SELECT * FROM "users"
```

A collector is an object that gathers the results as they come in from the
visitor. In this particular example, `collector` could have been a Ruby's own
String and we'd get the same result (without calling the final `value` of
course). If we look at the actual [source
code](https://github.com/rails/arel/blob/f50de54/lib/arel/tree_manager.rb#L27-L31)
of `to_sql`, we can see that it does the same except it gets the visitor
directly from the connection.

Let's take a look at one more visitor,
[Arel::Visitors::Dot](https://github.com/rails/arel/blob/f50de54/lib/arel/visitors/dot.rb).
The visitor generates the Graphviz's Dot format and we can use it to create
diagrams out of an AST. To make things easier, there's a convenient
[to_dot](https://github.com/rails/arel/blob/f50de54/lib/arel/tree_manager.rb#L17-L19)
method we can use. We take the output and save it to a file.

```ruby
File.write("arel.dot", select_manager.to_dot)
```

On the command line, we use the `dot` utility to convert the result to an image.

```bash
dot arel.dot -T png -o arel.png
```

<div class="image">
<a href="/images/arel/arel_to_dot.png">
<img src="/images/arel/arel_to_dot_small.png" title="fu" />
</a>
</div>

## Back to upper levels

We have all this power at our disposal at the Arel level but how can we leverage
it with ActiveRecord? Turns out that we can very easily get the underlying
`Arel::Table` directly from our models with `<Table>.arel_table`. What's even
better is that we can get the AST from our ActiveRecord's queries and
manipulate it. A word of warning though, working with the underlying Arel object
is not officially supported and things may change between releases without
notice.

First, we need a few throw-away tables and the corresponding ActiveRecord objects to work
against. Let's go again with users and comments.

```ruby
class User < ActiveRecord::Base
  connection.create_table table_name, force: true do |t|
    t.string :name, null: false
    t.integer :karma, null: false, default: 0
    t.boolean :vip, null: false, default: false
    t.timestamps
  end

  create! [{name: "Alice", karma: 999, vip: true}, {name: "Bob", karma: 1000}, {name: "Charlie"}]

  has_many :comments, dependent: :delete_all
end

class Comment < ActiveRecord::Base
  connection.create_table table_name, force: true do |t|
    t.text :text, null: false
    t.integer :points, null: false, default: 0
    t.references :user
    t.timestamps
  end

  belongs_to :user
end
```

As mentioned in the previous paragraph, we can get the `Arel::Table` object out
by calling
[arel_table](https://github.com/rails/rails/blob/178448/activerecord/lib/active_record/core.rb#L216-L218)
on the model. Once we do that, we can use the same methods as we've been using
so far throughout the text.

```ruby
u = User.arel_table
User.where(u[:karma].gteq(1000).or(u[:vip].eq(true))).to_a
# => [#<User id: 1, name: "Alice"...>, #<User id: 2, name: "Bob"...>]
```

Here we're passing an Arel node (`Arel::Nodes::Grouping`) directly to AR's
`where`. No need to convert anything as AR knows how to deal with these objects.
Let's switch the sides and use an AR query inside an Arel one.


```ruby
User.first.comments.create! text: "Sample text!", points: 1001

c             = Comment.arel_table
popular_users = User.select(:id).order(karma: :desc).limit(5)
comments      = c.project(Arel.star).where(c[:points].gt(1000).and(c[:user_id].in(popular_users.ast)))

Comment.find_by_sql(comments.to_sql)
```

To execute Arel queries, we first need to get the SQL out of Arel and then feed
it into
[find\_by\_sql](https://github.com/rails/rails/blob/178448/activerecord/lib/active_record/querying.rb#L38-L49).
Notice that we called `ast` on `popular_users` before passing it to Arel's
`in`. That's because `popular_users` is an instance of `ActiveRecord::Relation`
and we need to get the underlying Arel AST.

There of course comes a time when you need to issue a query that doesn't
necessarily result in records coming back.  In that case, we can use the
connection directly and call `execute` with the SQL as the argument.

```ruby
ActiveRecord::Base.connection.execute(c.where(c[:id].eq(1)).compile_delete.to_sql)
```

One issue you may run into when using ActiveRecord 4.1.x is that calling `to_sql`
might return an SQL query with bind parameters instead of the actual values. The
issue has been solved on the current master branch and will be part of the next
release. To get around that issue now however, we must use
`unprepared_statement`.

```ruby
# ActiveRecord 4.1.x

sql = User.first.comments.to_sql
# => SELECT "comments".* FROM "comments"  WHERE "comments"."user_id" = ?

sql = User.connection.unprepared_statement {
  User.first.comments.to_sql
}
# => SELECT "comments".* FROM "comments"  WHERE "comments"."user_id" = 1
```

The code in the `unprepared_statement` block gets evaluated with a visitor that
mixes in
[Arel::Visitors::BindVisitor](https://github.com/rails/arel/blob/f50de54/lib/arel/visitors/bind_visitor.rb),
which immediately resolves the bind parameters.

## Real world

Having covered all of that, how do we use this in a real word application so
that the code is maintainable and won't become a mess? One way of doing it is to
create a class that will represent our query. Let's take a look at a simple
example.

```ruby
class PrivilegedUsersQuery
  attr_reader :relation

  def initialize(relation = User.all)
    @relation = relation
  end

  def find_each(&block)
    relation.where(privileged_users).find_each(&block)
  end

  private

  def privileged_users
    with_high_karma.or with_vip
  end

  def with_high_karma
    table[:karma].gt(1000)
  end

  def with_vip
    table[:vip].eq(true)
  end

  def table
    User.arel_table
  end
end
```

We take full advantage of the fact that we can build queries iteratively and
dedicate a method to each part or similar, whatever feels like the best approach
for the particular situation.

```ruby
PrivilegedUsersQuery.new.find_each do |user|
 # ...
end
```


## The end

[Arel](https://github.com/rails/arel) is a great tool to build abstractions upon
and a powerful helper when the abstractions fail to provide the functionality
you need. By now you know everything there's to know to use Arel effectively and
most importantly you know where to look for answers when constructing a
complicated query or when things go wrong. Please let me know if you found an
error of any kind or have other suggestions.
