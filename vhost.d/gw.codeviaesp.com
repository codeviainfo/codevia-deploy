# Gateway LLM — ajustes de nivel `server`.
# Lo que afecta al streaming va en el fichero `_location`, no aquí.

# Un prompt con documentos adjuntos se va fácilmente por encima del
# 1 MB que nginx permite por defecto, y el 413 resultante no dice nada
# útil ni al empleado ni al SDK.
client_max_body_size 32m;
