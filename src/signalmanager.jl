module SignalManager

using React

function update(id::Int, val)
    #@vprintln ("coulda sent", id, val)
end

function start_update{T}(s::Signal{T})
    lift(v -> update(s.id, v), s)
end

function start_update{T}(s::Signal{T}, m::MIME)
    lift(v -> update(s.id, v), s)
end

end
