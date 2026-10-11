/* Native LittleCMS2 adapter. The official memory-handler plugin imposes a
 * 64 MiB aggregate CMM allocation budget; an eight-entry active LRU explicitly
 * closes evicted transforms. Retained descriptors reopen from borrowed profile
 * bytes, so eviction never leaves a dangling transform pointer.
 */
#include "moonbit.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "vendor/lcms2/include/lcms2_plugin.h"
#if defined(_WIN32)
#include <windows.h>
#define ICC_OPEN() LoadLibraryA("lcms2.dll")
#define ICC_SYM(h,n) GetProcAddress((HMODULE)h,n)
#else
#include <dlfcn.h>
#if defined(__APPLE__)
#define ICC_OPEN() dlopen("liblcms2.dylib", RTLD_LOCAL | RTLD_LAZY)
#else
#define ICC_OPEN() dlopen("liblcms2.so.2", RTLD_LOCAL | RTLD_LAZY)
#endif
#define ICC_SYM(h,n) dlsym(h,n)
#endif
#define ICC_ACTIVE_LIMIT 8
#define ICC_MEMORY_LIMIT ((size_t)64 * 1024 * 1024)
static cmsContext (*icc_context)(void *,void *);
static void (*icc_delete_context)(cmsContext);
static cmsHPROFILE (*icc_open)(cmsContext,const void *,cmsUInt32Number);
static cmsBool (*icc_close)(cmsHPROFILE);
static cmsHPROFILE (*icc_srgb)(cmsContext);
static cmsColorSpaceSignature (*icc_space)(cmsHPROFILE);
static cmsHTRANSFORM (*icc_create)(cmsContext,cmsHPROFILE,cmsUInt32Number,cmsHPROFILE,cmsUInt32Number,cmsUInt32Number,cmsUInt32Number);
static void (*icc_delete)(cmsHTRANSFORM);
static void (*icc_do)(cmsHTRANSFORM,const void *,void *,cmsUInt32Number);
static int icc_state;
int32_t pdf_icc_available(void) {
  if (icc_state) return icc_state == 1;
  void *lib=ICC_OPEN();icc_state=-1;if(!lib)return 0;
#define LOAD(p,n) do { *(void **)(&(p))=ICC_SYM(lib,n);if(!(p))return 0; } while(0)
  LOAD(icc_context,"cmsCreateContext");LOAD(icc_delete_context,"cmsDeleteContext");
  LOAD(icc_open,"cmsOpenProfileFromMemTHR");LOAD(icc_close,"cmsCloseProfile");
  LOAD(icc_srgb,"cmsCreate_sRGBProfileTHR");LOAD(icc_space,"cmsGetColorSpace");
  LOAD(icc_create,"cmsCreateTransformTHR");LOAD(icc_delete,"cmsDeleteTransform");LOAD(icc_do,"cmsDoTransform");
#undef LOAD
  icc_state=1;return 1;
}
typedef union { size_t size; long double align; void *pointer_align; } icc_allocation;
static size_t icc_allocated;
static void *icc_malloc(cmsContext context,cmsUInt32Number size) {
  (void)context;size_t total=(size_t)size+sizeof(icc_allocation);
  if(total>ICC_MEMORY_LIMIT-icc_allocated)return NULL;
  icc_allocation *p=(icc_allocation *)malloc(total);if(!p)return NULL;
  p->size=total;icc_allocated+=total;return p+1;
}
static void icc_free(cmsContext context,void *p) {
  (void)context;if(!p)return;icc_allocation *header=(icc_allocation *)p-1;
  icc_allocated-=header->size;free(header);
}
static void *icc_realloc(cmsContext context,void *p,cmsUInt32Number size) {
  if(!p)return icc_malloc(context,size);
  if(!size){icc_free(context,p);return NULL;}
  icc_allocation *header=(icc_allocation *)p-1;size_t old=header->size,total=(size_t)size+sizeof(*header);
  if(total>ICC_MEMORY_LIMIT-(icc_allocated-old))return NULL;
  header=(icc_allocation *)realloc(header,total);if(!header)return NULL;
  header->size=total;icc_allocated=icc_allocated-old+total;return header+1;
}
static void *icc_zero(cmsContext context,cmsUInt32Number size) {void *p=icc_malloc(context,size);if(p)memset(p,0,size);return p;}
static void *icc_calloc(cmsContext context,cmsUInt32Number n,cmsUInt32Number size) {
  if(n && size>UINT32_MAX/n)return NULL;return icc_zero(context,n*size);
}
static void *icc_dup(cmsContext context,const void *src,cmsUInt32Number size) {void *p=icc_malloc(context,size);if(p)memcpy(p,src,size);return p;}
static cmsPluginMemHandler icc_memory_plugin={{cmsPluginMagicNumber,2060,cmsPluginMemHandlerSig,NULL},icc_malloc,icc_free,icc_realloc,icc_zero,icc_calloc,icc_dup};
typedef struct {cmsHTRANSFORM transform;cmsContext context;int components;int intent;} pdf_icc_handle;
static pdf_icc_handle *active[ICC_ACTIVE_LIMIT];static int active_count;
static void release(pdf_icc_handle *h) {
  for(int i=0;i<active_count;i++)if(active[i]==h){for(int j=i+1;j<active_count;j++)active[j-1]=active[j];active_count--;break;}
  if(h->transform){icc_delete(h->transform);h->transform=NULL;}
  if(h->context){icc_delete_context(h->context);h->context=NULL;}
}
static void pdf_icc_destroy(void *p) {release((pdf_icc_handle *)p);}
static int activate(pdf_icc_handle *h,const uint8_t *bytes,int length) {
  if(h->transform){
    for(int i=0;i<active_count;i++)if(active[i]==h){for(int j=i+1;j<active_count;j++)active[j-1]=active[j];active[active_count-1]=h;break;}
    return 1;
  }
  if(!pdf_icc_available()||length<132||length>16*1024*1024)return 0;
  if(active_count>=ICC_ACTIVE_LIMIT)release(active[0]);
  h->context=icc_context(&icc_memory_plugin,NULL);if(!h->context)return 0;
  cmsHPROFILE input=icc_open(h->context,bytes,(uint32_t)length);
  if(!input){release(h);return 0;}
  cmsColorSpaceSignature expected=h->components==1?cmsSigGrayData:h->components==3?cmsSigRgbData:cmsSigCmykData;
  if(icc_space(input)!=expected){icc_close(input);release(h);return 0;}
  cmsHPROFILE output=icc_srgb(h->context);
  if(output){
    uint32_t format=h->components==1?TYPE_GRAY_DBL:h->components==3?TYPE_RGB_DBL:TYPE_CMYK_DBL;
    h->transform=icc_create(h->context,input,format,output,TYPE_RGB_DBL,(uint32_t)h->intent,0);
    icc_close(output);
  }
  icc_close(input);
  if(!h->transform){release(h);return 0;}
  active[active_count++]=h;return 1;
}
void *pdf_icc_open(const uint8_t *bytes,int32_t length,int32_t components,int32_t intent) {
  pdf_icc_handle *h=moonbit_make_external_object(pdf_icc_destroy,sizeof(*h));
  h->transform=NULL;h->context=NULL;h->components=components;h->intent=intent>=0&&intent<=3?intent:1;
  activate(h,bytes,length);return h;
}
int32_t pdf_icc_valid(pdf_icc_handle *h){return h->transform!=NULL;}
int32_t pdf_icc_convert(pdf_icc_handle *h,const uint8_t *bytes,int32_t length,double a,double b,double c,double d,double *output) {
  if(!activate(h,bytes,length))return 0;
  double scale=h->components==4?100.0:1.0,input[4]={a*scale,b*scale,c*scale,d*scale};
  icc_do(h->transform,input,output,1);return 1;
}
void pdf_icc_clear_active(void){while(active_count)release(active[0]);}
int32_t pdf_icc_active_count(void){return active_count;}
int32_t pdf_icc_allocated_bytes(void){return (int32_t)icc_allocated;}
