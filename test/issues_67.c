/*
 * https://github.com/kjdev/hoextdown/issues/67
 *
 * Regression test for pointer underflow in hoedown_autolink__url and
 * hoedown_autolink__email caused by the unsigned promotion of `-1 - rewind`.
 * Built with AddressSanitizer + UndefinedBehaviorSanitizer; the previous
 * implementation reliably tripped UBSan ("addition of unsigned offset
 * overflowed") on any autolink input where max_rewind > 0.
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#include "buffer.h"
#include "document.h"
#include "html.h"

static void
render(const char *input)
{
	hoedown_extensions ext = (hoedown_extensions)HOEDOWN_EXT_AUTOLINK;
	hoedown_buffer *ob = hoedown_buffer_new(64);
	hoedown_renderer *renderer = hoedown_html_renderer_new((hoedown_html_flags)0, 0);
	hoedown_document *doc = hoedown_document_new(
		renderer, ext, /*max_nesting=*/16, /*attr_activation=*/0,
		/*user_block=*/NULL, /*meta=*/NULL);

	hoedown_document_render(doc, ob, (const uint8_t *)input, strlen(input));

	hoedown_document_free(doc);
	hoedown_html_renderer_free(renderer);
	hoedown_buffer_free(ob);
}

int
main(void)
{
	/* URL autolink: triggers hoedown_autolink__url with max_rewind > 0,
	 * which is the exact site reported in issue #67 (autolink.c:252). */
	render("see http://example.com here");

	/* Email autolink: same unsigned-promotion problem at autolink.c:195. */
	render("contact user@example.com today");

	return 0;
}
