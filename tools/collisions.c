#include "viet_engine.h"
#include <stdio.h>
#include <string.h>
static void put(uint32_t cp){ if(cp<0x80)putchar(cp); else if(cp<0x800){putchar(0xC0|(cp>>6));putchar(0x80|(cp&0x3F));} else {putchar(0xE0|(cp>>12));putchar(0x80|((cp>>6)&0x3F));putchar(0x80|(cp&0x3F));}}
int main(int argc,char**argv){ ve_engine*e=ve_new(); ve_set_english_check(e,0); if(argc>1&&!strcmp(argv[1],"vni"))ve_set_method(e,VE_VNI);
 char w[128]; while(scanf("%127s",w)==1){ ve_reset(e); for(char*p=w;*p;p++) ve_process_key(e,(unsigned char)*p);
  uint32_t o[128]; int n=ve_current_word(e,o,128); int same=(n==(int)strlen(w)); for(int i=0;same&&i<n;i++) same=o[i]==(unsigned char)w[i];
  if(!same){ printf("%s\t",w); for(int i=0;i<n;i++)put(o[i]); putchar('\n'); } } }
