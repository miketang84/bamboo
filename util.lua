module(..., package.seeall)

function simpleRender(tmpl_file, params)
  return web:html(tmpl_file, params)
end


