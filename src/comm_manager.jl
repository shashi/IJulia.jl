module CommManager

using IJulia

import IJulia: Msg, uuid4, send_ipython, send_status, publish,
               execute_msg, msg_pub

export Comm, comm_id, msg_comm, send_comm, close_comm, on_msg,
       on_close, register_comm, comm_msg, comm_open, comm_close


immutable Comm{target, id}
    primary::Bool
end


function Comm(t)
    # Create a new primary Comm with target t, and a new id
    comm = Comm{symbol(t), symbol(uuid4())}(true)
    # Request a secondary Comm object in the frontend
    send_ipython(IJulia.publish,
                 msg_comm(comm, IJulia.execute_msg, "comm_open",
                          Dict(), target_name=string(t)))
    comms[comm.id] = comm
    return comm
end

Comm(t, id, primary=false) =
    Comm{symbol(t), symbol(id)}(primary)


comm_id{target, id}(comm :: Comm{target, id}) = id
comm_target{target, id}(comm :: Comm{target, id}) = target


const comms   = Dict{String, Comm}()
const parents = Dict{Comm, IJulia.Msg}()


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
    parent = get!(parents, comm, IJulia.execute_msg)
    msg = msg_comm(comm, parent, "comm_msg", data,
                   metadata; kwargs...)
    send_ipython(IJulia.publish, msg)
    parents[comm] = msg
end


function close_comm(comm::Comm, data::Dict = Dict(),
                    metadata::Dict = Dict(); kwargs...)
    parent = get!(parents, comm, IJulia.execute_msg)
    msg = msg_comm(comm, parent, "comm_msg", data,
                   metadata; kwargs...)
    send_ipython(IJulia.publish, msg)
    parents[comm] = msg
end

function register_comm(comm::Comm, data)
    # no-op, widgets must override for their targets.
    # Method dispatch on Comm{t} serves
    # the purpose of register_target in IPEP 21.
end

function on_msg(comm::Comm, msg)
    # comm_msg message handler
end

function on_close(comm::Comm, msg)
    # comm_close message handler
end


# handlers for incoming comm_* messages

function comm_open(sock, msg)
    if haskey(msg.content, "comm_id")
        send_status("busy")
        comm_id = msg.content["comm_id"]
        if haskey(msg.content, "target_name")
            target = msg.content["target_name"]
            if !haskey(msg.content, "data")
                msg.content["data"] = Dict()
            end
            comm = Comm(target, comm_id)
            register_comm(comm, msg)
            comms[comm_id] = comm
        else
            # Tear down comm to maintain consistency
            # if a target_name is not present
            send_ipython(IJulia.publish,
                         msg_comm(Comm(:notarget, comm_id),
                                  msg, "comm_close"))
        end
        send_status("idle")
    end
end


function comm_msg(sock, msg)
    if haskey(msg.content, "comm_id")
        send_status("busy")
        comm_id = msg.content["comm_id"]
        if haskey(comms, comm_id)
            comm = comms[comm_id]
        else
            # We don't have that comm open
            return
        end

        if !haskey(msg.content, "data")
            msg.content["data"] = Dict()
        end
        on_msg(comm, msg)
        parents[comm] = msg
        send_status("idle")
    end
end


function comm_close(sock, msg)
    if haskey(msg.content, "comm_id")
        send_status("busy")
        comm_id = msg.content["comm_id"]
        comm = comms[comm_id]

        if !haskey(msg.content, "data")
            msg.content["data"] = {}
        end
        on_close(comm, msg)

        delete!(comms, comm.id)
        delete!(parents, comm)
        send_status("idle")    
    end
end


end # module
