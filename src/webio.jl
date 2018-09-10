using IJulia
using IJulia.CommManager
using WebIO

import WebIO: AbstractConnection

struct IJuliaConnection <: AbstractConnection
    comm::CommManager.Comm
end

function WebIO.send(c::IJuliaConnection, data)
    send_comm(c.comm, data)
end

Base.isopen(c::IJuliaConnection) = haskey(IJulia.CommManager.comms, c.comm.id)

function webio_setup()
    if !IJulia.inited
        # If IJulia has not been initialized and connected to Jupyter itself,
        # then we have no way to display anything in the notebook and no way
        # to set up comms, so this function cannot run. That's OK, because 
        # any IJulia kernels will start up with a fresh process and a fresh 
        # copy of WebIO and IJulia. 
        return
    end
    prefix = WebIO.baseurl[] * "/" * AssetRegistry.register(WebIO.assetpath)

    display(HTML("<script class='js-collapse-script' src='$prefix/webio/dist/bundle.js'></script>"))
    display(HTML("<script class='js-collapse-script' src='$prefix/providers/ijulia_setup.js'></script>"))

    display(HTML("""
      <script class='js-collapse-script'>
        \$('.js-collapse-script').parent('.output_subarea').css('padding', '0');
      </script>
    """))

    comm = Comm(:webio_comm)
    conn = IJuliaConnection(comm)
    comm.on_msg = function (msg)
        data = msg.content["data"]
        WebIO.dispatch(conn, data)
    end
    nothing
end
