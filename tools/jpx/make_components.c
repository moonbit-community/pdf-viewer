#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "openjpeg.h"
int main(int argc,char **argv) {
 if(argc<5)return 2;
 int prec=atoi(argv[2]),sgnd=atoi(argv[3]),sub=atoi(argv[4]),nc=sub?3:1;
 opj_cparameters_t p;opj_set_default_encoder_parameters(&p);p.tcp_numlayers=1;p.tcp_rates[0]=0;p.cp_disto_alloc=1;p.numresolution=1;p.tcp_mct=0;
 opj_image_cmptparm_t c[3];memset(c,0,sizeof(c));
 for(int k=0;k<nc;k++){c[k].prec=prec;c[k].sgnd=sgnd;c[k].dx=c[k].dy=(sub&&k)?2:1;c[k].w=(7+c[k].dx-1)/c[k].dx;c[k].h=(3+c[k].dy-1)/c[k].dy;}
 opj_image_t *im=opj_image_create(nc,c,sub?OPJ_CLRSPC_SYCC:OPJ_CLRSPC_GRAY);im->x1=7;im->y1=3;
 for(int k=0;k<nc;k++)for(unsigned y=0;y<c[k].h;y++)for(unsigned x=0;x<c[k].w;x++){int v=(x*19+y*53+k*71)&((1<<prec)-1);im->comps[k].data[y*c[k].w+x]=v-(sgnd?(1<<(prec-1)):0);}
 opj_codec_t *codec=opj_create_compress(OPJ_CODEC_J2K);if(!opj_setup_encoder(codec,&p,im))return 3;
 opj_stream_t *s=opj_stream_create_default_file_stream(argv[1],0);int ok=opj_start_compress(codec,im,s)&&opj_encode(codec,s)&&opj_end_compress(codec,s);opj_stream_destroy(s);opj_destroy_codec(codec);opj_image_destroy(im);return !ok;
}
