module IJReactiveDisplay

using React

import Base: display
import IPythonDisplay: display, InlineDisplay

immutable ReactiveDisplay <: Display end

signaldict = Dict{Int, Signal}

function notify_change(id :: Int, x)
    #### 
    println("Updating ", id, " ", x)
end

function recv_change(id :: Int, x)
    println("Received ", id, " ", x)
    if haskey(id, signaldict)
        push!(signaldict[id], x)
    else
        error("Received  update from unregistered inbound signal #$(id)")
    end
end

function register_outbound(s :: Signal)
    #XXX: Congestion control?
    update(x) = notify_change(s.id, x)
    lift(update, s)
end

function register_inbound(s :: Signal)
    signaldict[s.id] = s
end

function display(d::ReactiveDisplay, m::MIME, x <: Signal{T})
    register_outbound(x)
    display(d, m, x.value, {reactive=>true,
                      signal_id=>x.id})
end

function display(d::ReactiveDisplay, x <: Signal{T})
    register_outbound(x)
    display(d, x.value, {reactive=>true,
                   signal_id=>x.id})
end

end
