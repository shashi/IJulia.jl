module CommManager

using IJulia

import IJulia: Msg, uuid4, send_ipython, publish, execute_msg, msg_pub

export Comm, msg_comm, send_comm, close_comm, on_msg,
       on_close, register_target, comm_msg, comm_open, comm_close


immutable Comm{target}
    id::String
    primary::Bool
end


function Comm(t)
    # Create a new primary Comm with target t
    comm = Comm{symbol(t)}(uuid4(), true)
    # Is this the right parent for a comm_open?
    global execute_msg, publish
    # Create a secondary Comm object in the frontend
    send_ipython(IJulia.publish,
                 msg_comm(comm, IJulia.execute_msg, "comm_open",
                          Dict(), target_name=string(t)))
    comms[comm.id] = comm
    return comm
end

Comm(t, id, primary=false) = Comm{symbol(t)}(id, primary)


const comms               = Dict{String, Comm}()
const comm_msg_handlers   = Dict{Comm, Function}()
const comm_close_handlers = Dict{Comm, Function}()
const parents             = Dict{Comm, IJulia.Msg}()


function msg_comm(comm::Comm, m::IJulia.Msg, msg_type,
                  data=Dict{String,Any}(),
                  metadata=Dict{String, Any}(); kwargs...)
    content = ["comm_id"=>comm.id,
               "data"=>data]

    for (k, v) in kwargs
        content[string(k)] = v
    end

    return msg_pub(m, msg_type, content, metadata)
end


function send_comm(comm::Comm, data::Dict,
                   metadata::Dict = Dict(); kwargs...)
    global publish
    parent = get!(parents, comm, IJulia.execute_msg)
    msg = msg_comm(comm, parent, "comm_msg", data,
                   metadata; kwargs...)
    send_ipython(IJulia.publish, msg)
    parents[comm] = msg
end


function close_comm(comm::Comm, data::Dict = Dict(),
                    metadata::Dict = Dict(); kwargs...)
    parent = get!(parents, comm, IJulia.execute_msg)
    global publish
    msg = msg_comm(comm, parent, "comm_msg", data,
                   metadata; kwargs...)
    send_ipython(IJulia.publish, msg)
    parents[comm] = msg
end


function on_msg(comm::Comm, f::Function)
    comm_msg_handlers[comm] = f
end

function on_close(comm::Comm, f::Function)
    comm_close_handlers[comm] = f
end


function register_comm(comm::Comm, data)
    # no-op, widgets must override for their targets.
    # Method dispatch on Comm{t} serves
    # the purpose of register_target in IPEP 21.
end


# handlers for incoming comm_* messages

function comm_open(sock, msg)
    if haskey(msg.content, "comm_id")
        comm_id = msg.content["comm_id"]
        if haskey(msg.content, "target_name")
            target = msg.content["target_name"]
            if !haskey(msg.content, "data")
                msg.content["data"] = Dict()
            end
            comm = Comm(symbol(target), comm_id)
            register_comm(comm, msg)
            comms[comm.id] = comm
        else
            # Tear down comm to maintain consistency
            # if a target_name is not present
            global publish
            send_ipython(IJulia.publish,
                         msg_comm(Comm(:notarget, comm_id),
                                  msg, "comm_close"))
        end
    end
end


function comm_msg(sock, msg)
    if haskey(msg.content, "comm_id")
        comm_id = msg.content["comm_id"]
        if haskey(comms, comm_id)
            comm = comms[comm_id]
        else
            # We don't have that comm open
            return
        end
        if haskey(comm_msg_handlers, comm)
            if !haskey(msg.content, "data")
                msg.content["data"] = Dict()
            end
            comm_msg_handlers[comm](msg)
        end
        parents[comm] = msg
    end
end


function comm_close(sock, msg)
    if haskey(msg.content, "comm_id")
        comm_id = msg.content["comm_id"]
        comm = comms[comm_id]
        if haskey(comm, comm_close_handlers)
            if !haskey(msg.content, "data")
                msg.content["data"] = {}
            end
            comm_close_handlers[comm](msg)
            delete!(comm_close_handlers, comm)
        end
        if haskey(comm_msg_handlers, comm)
            delete!(comm_msg_handlers, comm)
        end
        delete!(comms, comm.id)
    end
end


end # module
