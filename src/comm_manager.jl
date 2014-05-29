module CommManager

import IJulia
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
    global execute_msg
    # Create a secondary Comm object in the frontend
    send_ipython(publish,
                 msg_comm(comm, execute_msg, "comm_open",
                          data=["target_name"=>string(t)]))
    comms[comm.id] = comm
    return comm
end

Comm(t, id, primary=false) = Comm{symbol(t)}(id, primary)


const comms               = Dict{String, Comm}()
const comm_msg_handlers   = Dict{Comm, Function}()
const comm_close_handlers = Dict{Comm, Function}()
const parents             = Dict{Comm, Msg}()


function msg_comm(comm::Comm, m::Msg, msg_type,
                  data=Dict{String,Any}(),
                  metadata=Dict{String, Any}(); kwargs...)
    content = ["comm_id"=>comm.id,
               "data"=>data]

    for (k, v) in kwargs
        content[k] = v
    end

    return msg_pub(m, msg_type, content,
                   metadata=metadata)
end

function send_comm(comm::Comm, data::Dict,
                   metadata::Dict = Dict(); kwargs...)
    parent = get!(parents, comm, execute_msg)
    msg = msg_comm(comm, parent, "comm_msg", data,
                   metadata; kwargs...)
    send_ipython(publish, msg)
    parents[comm] = msg
end

function close_comm(comm::Comm, data::Dict = Dict(),
                    metadata::Dict = Dict(); kwargs...)
    parent = get!(parents, comm, execute_msg)
    msg = msg_comm(comm, parent, "comm_msg", data,
                   metadata; kwargs...)
    send_ipython(publish, msg)
    parents[comm] = msg
end

function on_msg(comm::Comm, f::Function)
    comm_msg_handlers[comm] = f

end

function on_close(comm::Comm, f::Function)
    comm_close_handlers[comm] = f
end

function register_comm(comm::Comm, data::Dict() = Dict())
    # no-op, widgets must override for their targets.
    # Method dispatch on Comm{t} serves
    # the purpose of register_target in IPEP 21.
end

# handlers for incoming comm_* messages
function comm_open(sock, msg)
    if haskey("comm_id", msg.content)
        comm_id = msg.content["comm_id"]
        if haskey("target_name", msg.content)
            target = msg.content["target_name"]
            if ~haskey("data", msg.content)
                msg.content["data"] = Dict()
            end
            register_comm(comm, msg)
            comms[comm.id] = comm
        else
            # Tear down comm to maintain consistency
            # if a target_name is not present
            send_ipython(publish,
                         msg_comm(Comm(:notarget, comm_id),
                                  msg, "comm_close"))
        end
    end
end

function comm_msg(sock, msg)
    if haskey("comm_id", msg.content)
        comm_id = msg.content["comm_id"]
        if haskey(comm_id, comms)
            comm = comms[comm_id]
        else
            # We don't have that comm open
            return
        end
        if haskey(comm, comm_msg_handlers)
            if ~haskey("data", msg.content)
                msg.content["data"] = Dict()
            end
            comm_msg_handlers[comm](msg)
        end
        parents[comm] = msg
    end
end

function comm_close(sock, msg)
    if haskey("comm_id", msg.content)
        comm_id = msg.content["comm_id"]
        comm = comms[comm_id]
        if haskey(comm, comm_close_handlers)
            if ~haskey("data", msg.content)
                msg.content["data"] = {}
            end
            comm_close_handlers[comm](msg)
            pop!(comm_close_handlers, comm)
        end
        if haskey(comm_msg_handlers, comm)
            pop!(comm_msg_handlers, comm)
        end
        if haskey(comms, comm.id)
            pop!(comms, comm.id)
        end
    end
end

end # module
