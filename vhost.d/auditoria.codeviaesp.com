# Panel de Auditoria de IA — ajustes de nivel `server` para nginx-proxy.

# El comando de auditoria envia el uso con planes de un empleado de una
# vez (unos 90 KB por mes y medio de uso intenso; meses enteros pueden
# pasar del 1 MB que nginx permite por defecto). El 413 resultante no le
# diria nada util al empleado. La API admite 10 MB en esa ruta y 256 KB
# en el resto, y el nginx del propio panel aplica lo mismo.
client_max_body_size 10m;
