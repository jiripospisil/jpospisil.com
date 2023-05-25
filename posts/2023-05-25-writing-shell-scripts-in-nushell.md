---
title: Writing shell scripts in Nushell
is_draft: false
layout: post.liquid
permalink: /2023/05/25/writing-shell-scripts-in-nushell.html
---

I don’t like Bash. It’s just too confusing. Do I need to use double brackets
for this? Do I need to quote this? Am I still writing [Bash] or am I sprinkling in
some bits of [sh]? I can never remember.

[Bash]: https://en.wikipedia.org/wiki/Bash_(Unix_shell) 
[sh]: https://en.wikipedia.org/wiki/Bourne_shell

```bash
if [ -n $var ]   # All sorts of wrong
if [ -n "$var" ] # POSIX
if [[ -n $var ]] # Bash
```

*Tip: If you are stuck writing Bash scripts, use [ShellCheck] to check it for bugs.*

[ShellCheck]: https://www.shellcheck.net

At the same time I keep finding myself writing shell scripts because sometimes
it’s just so damn convenient. Sure, I could use a *real* programming language but
it gets annoying pretty quickly when the script is really just driving external
commands.

Let's try using [Nushell]. I will let you peruse their website on your own but
the key takeaways are that Nushell is a modern alternative that tries to avoid
many of the pitfalls of Bash (and other shells) and to provide a sane scripting
environment.

[Nushell]: https://www.nushell.sh

<div class="image">
  <img src="/posts/nushell/1.png" title="57MB? Outrages! In all seriousness, it should consume less.">
</div>

You will also notice that in Nushell you work with structured data. Each of the
commands understands what’s being passed in. That's probably a bit controversial
among UNIX enthusiasts who prefer using plain text but honestly I don't really
mind. Reminds me of [PowerShell].

[PowerShell]: https://github.com/PowerShell/PowerShell

Of course the same thing could be achieved in other shells but it’s often either
more involved or hard to remember.

```bash
# Bash / Zsh
find . -maxdepth 1 -type f -size +10M -exec ls -lh --sort=time -r {} +

# Zsh
ls -lh *(Lm+10om) --sort=time -r
```

*Tip: Have a look at [A Guide to Zsh Expansion with Examples] for more Zsh wizardry.*

[A Guide to Zsh Expansion with Examples]: https://thevaluable.dev/zsh-expansion-guide-example

Using Nushell as an actual terminal shell is all good and well but I think a
more interesting use case is to use it to write scripts.

As an exercise, let’s write a script that will sum all the numbers passed in as
arguments. Nushell scripts are executed top to bottom as any other scripts, but
to get access to command line arguments, we do need to define a main function.

```nushell
def main [...numbers] {
  # 1.
  mut total = 0
  
  for number in $numbers {
    $total += ($number | into int)
  }

  print $total

  # 2.
  print ($numbers | reduce { |it, acc| $it + $acc })

  # 3.
  print ($numbers | math sum)
}
```

```
./sum.nu 1 2 3
6
6
6
```

Passing in a string instead of a number will make the script rightfully angry.
We can do better and declare that we want accept integers only.

```nushell
def main [...numbers: int]
```

The difference is that now the body of the function will not get to run and
we get a nice error message. Imagine a wild project manager comes in and says
we need to accept a flag which will determine whether to sum or multiply the
numbers.

```nushell
# A command to work on numbers
def main [
  ...numbers: int, # Numbers to work on
  --multiply (-m)  # Operation to perform
  ] {
    if ($numbers | is-empty) {
      help main | print -e
      exit 1
    }

    if $multiply {
      print ($numbers | math mul)
    } else {
      print ($numbers | math sum)
    }
}
```

```
./sum.nu 1 2 3 4 --multiply # or -m
24
./sum.nu 1 2 3 4
10
```

Notice that the flag doesn't have a type. In this case, Nushell takes the
presence or absence of the flag as the bool value. If we had specified an
explicit bool type, we would have to pass in a value on the command line e.g.
“-m true”.

The comments next to the function’s arguments are used for the auto-generated
documentation. Notice that we can print the documentation programmatically to
show “usage” in case we get an invalid input.

```
./sum.nu --help
A command to work on numbers

Usage:
  > main {flags} ...(numbers) 

Flags:
  -m, --multiply - Operation to perform
  -h, --help - Display the help message for this command

Parameters:
  ...numbers <int>: Numbers to work on 
```

The sub-command "mul” actually doesn't exist in the [standard library] but we can add it a basic version of it.

[standard library]: https://www.nushell.sh/commands

```nushell
def "math mul" [] {
  $in | reduce { |it, acc| $it * $acc }
}
```

Okay, so it’s very easy to accept command line arguments and flags. What about
running some external programs? After all, all we've done so far is stay within
the Nushell’s runtime.

Let’s write a script which will return two of the latest commits for a given
GitHub repository using curl and [jq].

[jq]: https://stedolan.github.io/jq

```nushell
def main [
  name: string # Format: username/repository
  ] {
    if $name !~ \A[a-zA-Z0-9-_.]+/[a-zA-Z0-9-_.]+\z {
      help main | print -e
      exit 1
    }

    let url = $"https://api.github.com/repos/($name)/commits"

    curl -s $url
      | jq '[.[] | { author: .commit.author.name, msg: .commit.message[:20] }][:2]'
      | from json 
}
```

The meat of the script is not very different from what we would write in Bash.

```
./git.nu nushell/nushell
```

<div class="image">
  <img src="/posts/nushell/2.png">
</div>


What happens if we pass in a project name which doesn't exist?

```
./git.nu nushell/nushell2
jq: error (at <stdin>:4): Cannot index string with string "commit"
```

Well, that’s not great. The problem is that the request technically succeeded
but returned HTTP 404. We can tell curl to return a non-zero exit code in case
of server errors and to not output anything.

```
curl --fail -s $url | jq ...
```

Alright, now curl returns exit code 22 on any HTTP error and doesn't pass any
data forward which in turn makes jq output nothing.

```
./git.nu nushell/nushell2
```

But what if we wanted to write a message informing the user that the repository
was not found? We can use [complete] to capture the output and exit code.

[complete]: https://www.nushell.sh/commands/docs/complete.html

```nushell
let response = (curl --fail -s $url | complete)

match $response.exit_code {
  0 => {
    $response.stdout | jq ...
  },
  22 => {
    print -e $"Project \"($name)\" not found or server error!"
    exit 1
  },
  - => {
    print -e "It's all broken."
    exit 1
  }
}
```

```
./git.nu nushell/nushell2
Project "nushell/nushell2" not found!
```

Alright, we can invoke external commands, capture the exit code and the output.
Not everything is hunky-dory however. In Bash, it’s good hygiene to always start
your scripts with a set command to make it behave in a sane-er manner.

```
set -eu -o pipefail
```

This tells Bash to exit on any non-zero exit code, undefined variables, and use
the last non-zero exit code in a pipe as the exit code of the whole pipe.

The internet is full of discussions on whether these options make things better
or worse, but it’s worth noting that while Nushell will report usage of any
undefined variables (and missing external commands!), exit on error, it will NOT
propagate the pipe error when using external commands.

```
cat missing | wc -c
print "Hm!"
```

```
./pipe.nu  
cat: missing: No such file or directory
0
Hm!
```

The cat command fails, the wc command succeeds but doesn't receive any data. And
crucially, the next line is still executed. The default behavior in Bash is the
same but we can change it.

```
set -eu -o pipefail

cat missing | wc -c
echo "Hm!"
```

```
./pipe.bash 
cat: missing: No such file or directory
0
```

What if we wanted the same behavior in Nushell? We can achieve it using the [do]
command, albeit it makes working with external commands a bit awkward.

[do]: https://www.nushell.sh/commands/docs/do.html

```
do -c { cat missing } | wc -c
print "Hm!"
```

<div class="image">
  <img src="/posts/nushell/3.png">
</div>


Unfortunately, we cannot wrap the whole pipeline in a do, we would have to do it
individually for every external command in the pipeline.

*Note that handling of external commands is still work in progress and it’s very
likely to change in the future.*

While we’re at it, you might be wondering why dealing with exit codes is even a
thing. After all, exit code 0 indicates success, otherwise it’s an error. Right?
Unfortunately, there’s a lot of commands which [do not follow these rules]. Take
diff for example.

[do not follow these rules]: https://www.jntrnr.com/exit-codes

> Exit code is 0 if inputs are the same, 1 if different, 2 if trouble.

No matter how shells deal with exit codes of external commands, there will
eventually be a situation where the default behavior is not what you want. Oh
well.

Let’s get back to our little Git example. The script uses external commands to
do the heavy lifting of interacting with the network and parsing of the result.
While it works and is probably one of the ways one would do it in Bash, it
certainly isn't the “go-to” solution in Nushell.

Nushell has a fairly rich (and ever expanding) [standard library] for dealing with
the most common problems. Let’s try to rewrite the example using just Nushell’s
built-in [Network] commands.

[standard library]: https://www.nushell.sh/commands
[Network]: https://www.nushell.sh/commands/categories/network.html

Instead of using curl, we can use the built-in [http get] command. This of course
doesn't support all of the curl’s hundreds of options and features, but our use
case is really trivial.

[http get]: https://www.nushell.sh/commands/docs/http_get.html

```nushell
let response = (http get -f -e $url)

match $response.status {
  200 => {
    $response.body
      | select commit 
      | take 2
      | each { |it| 
        { 
          author: $it.commit.author.name 
          msg: ($it.commit.message | str substring 0..20)
        }
      }
  },
  404 => { ... },
  _ => { ... }
}
```

The output is exactly the same table as before. Besides the networking support,
we’re also taking advantage of Nushell’s ability to filter and reach into tables
and records.

This code also handles errors better. Those pipes run entirely within the
runtime using the built-in commands which means we don’t have to worry about
exit codes and command termination.

If we didn't want to provide a different message based on the HTTP status, we
could take advantage of [try/catch] to simply the code even further. It’s worth
noting that this mechanism seems to work as expected for built-in commands only.

[try/catch]: https://www.nushell.sh/commands/docs/try.html

```nushell
try {
  ...
} catch { |e|
  print -e $"An error occurred! ($e)"
}
```

In fact, since we’re just adding a prefix to the error message, we can take get
rid of the error handling all together and let the code fail.

```nushell
def main [
  name: string # Format: username/repository
  ] {
    if $name !~ \A[a-zA-Z0-9-_.]+/[a-zA-Z0-9-_.]+\z {
      help main | print -e
      exit 1
    }

    let url = $"https://api.github.com/repos/($name)/commits"

    http get $url 
      | select commit 
      | take 2
      | each { |it| 
          { 
            author: $it.commit.author.name 
            msg: ($it.commit.message | str substring 0..20)
          }
        }
}
```

In fact, in this case, we get a much better error message without the explicit
error handling that’s even pointing to the problem and prints context. Nice.

<div class="image">
  <img src="/posts/nushell/4.png">
</div>

Alright, that’s a long enough introduction. Going forward, I think I've
convinced myself to try creating scripts in Nushell first and only fallback to
alternatives in case of trouble. Let’s mention a few disadvantages to close off.

First, Nushell is a new shell and a scripting language that’s intentionally not
backwards compatible with other shells. This means learning a completely new
environment and all its quirks and features.

Second, Nushell has not reached a v1.0 (currently at v0.80). This means things
are still evolving and releases sometimes come with a few breaking changes,
potentially breaking your existing scripts. You might want to wait for things to
settle down.

Third, there’s a pretty good chance that everybody has Bash installed on their
system (let’s pretend Windows doesn't exist). Not so much with Nushell. It has
made its way to almost every distribution’s package manager out there ([I use
Arch btw]) but depending on your circumstances you might be out of luck.

[I use Arch btw]: https://knowyourmeme.com/memes/btw-i-use-arch

The good news here however is that if you do have it available and stay
within the standard library, your scripts should work on all Nushell supported
platforms out of the box.

<div class="image">
  <img src="/posts/nushell/5.png">
</div>

