module IPythonDisplay

using IJulia
using React
using SignalManager

import IJulia: send_ipython, publish, msg_pub, execute_msg, display_dict, displayqueue, undisplay

import Base: display, redisplay
export display, redisplay, InlineDisplay, ReactiveDisplay, undisplay

immutable InlineDisplay <: Display end
immutable ReactiveDisplay <: Display end

# supported MIME types for inline display in IPython, in descending order
# of preference (descending "richness")
const ipy_mime = [ "text/html", "text/latex", "image/svg+xml", "image/png", "image/jpeg", "text/plain" ]

for mime in ipy_mime
    @eval begin
        function display(d::InlineDisplay, ::MIME{symbol($mime)}, x, metadata=Dict())
            send_ipython(publish, 
                         msg_pub(execute_msg, "display_data",
                                 ["source" => "julia", # optional
                                  "metadata" => metadata, # optional
                                  "data" => [$mime => stringmime(MIME($mime), x)] ]))
        end
    end
end

# deal with annoying application/x-latex == text/latex synonyms
display(d::InlineDisplay, m::MIME"application/x-latex", x) = display(d, MIME("text/latex"), stringmime(m, x))

# override display to send IPython a dictionary of all supported
# output types, so that IPython can choose what to display.
function display(d::InlineDisplay, x, metadata=Dict())
    undisplay(x) # dequeue previous redisplay(x)
    send_ipython(publish, 
                 msg_pub(execute_msg, "display_data",
                         ["source" => "julia", # optional
                          "metadata" => metadata, # optional
                          "data" => display_dict(x) ]))
end

# we overload redisplay(d, x) to add x to a queue of objects to display,
# with the actual display occuring when display() is called or when
# an input cell has finished executing.

function redisplay(d::InlineDisplay, x)
    if !in(x,displayqueue)
        push!(displayqueue, x)
    end
end

function display()
    q = copy(displayqueue)
    empty!(displayqueue) # so that undisplay in display(x) is no-op
    for x in q
        display(x)
    end
end

# Reactive display functions
function display{T}(d::ReactiveDisplay, x::Signal{T})
    start_update(x)
    display(x.value, metadata = {reactive=>true,
                                 signal_id=>x.id})
end

function display{T}(d::ReactiveDisplay, m::MIME, x::Signal{T})
    start_update(x, m)
    display(m, x.value, metadata = {reactive=>true,
                                    signal_id=>x.id})
end

end # module
