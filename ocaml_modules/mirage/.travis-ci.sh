eval `opam config env`
opam depext -uiy mirage
cd ~
git clone -b master https://github.com/mirage/mirage-skeleton.git
make -C mirage-skeleton && rm -rf mirage-skeleton
