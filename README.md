MishMesh
========
iOS library for viewing 3D files. Delivered in the form of a static library which exposes everything you need to render 3D meshes. This repository includes a sample app project which demonstrates how this work can be easily integrated into another project. A quick demo of this library's features can be seen here: <http://youtu.be/ahDldv0AnMc>

Limitations
===========
- *File Formats*: Currently, only the obj file format is supported, however, it is trivial to add parsers for other file types. Support for this file format was implemented first due to both its popularity and simplicity. Support for 3ds is planned next.
- *Number Of Vertices*: The renderer will not draw files that use more than 65536 distinct vertices to define the geometry. OpenGL only lets one use an unsigned short to index into a vertex buffer, so this limitation was put in place to make my life easier. At some point, I might add the functionality for the framework to simply render models in batches of 64K as separate pieces of geometry.
