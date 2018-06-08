define([
    './webio-bundle',
    'base/js/namespace'
], function(
    x,
    Jupyter
) {
    function load_ipython_extension() {
        console.log(
            'This is the current notebook application instance:',
            Jupyter.notebook
        );
        console.log("WebIO", x)
    }

    return {
        load_ipython_extension: load_ipython_extension
    };
});
