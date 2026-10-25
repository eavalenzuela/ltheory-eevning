#ifndef LTE_Screenshot_h__
#define LTE_Screenshot_h__

#include "Common.h"
#include "String.h"

/* Screenshots are requested at any point during a frame and written when the
   frame is complete (Screenshot_Flush, called by the program just before the
   frame is presented), so they always contain a fully drawn image. */

/* Queue a screenshot named 'name'.png; an empty name picks the next free
   number. */
LT_API void Screenshot_Request(String const& name);

/* Write all queued screenshots from the current back buffer. */
LT_API void Screenshot_Flush();

/* Where screenshots are written (default: <user data>/screenshot/). */
LT_API void Screenshot_SetDirectory(String const& directory);

/* Shrink saved images by an integer factor (default 1). */
LT_API void Screenshot_SetDownscale(uint factor);

#endif
