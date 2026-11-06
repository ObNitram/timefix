using System.Text;
using System.Xml;
using System.Xml.Linq;

namespace TimeFix.Server.CalDav;

public static class Ns
{
    public static readonly XNamespace Dav = "DAV:";
    public static readonly XNamespace CalDav = "urn:ietf:params:xml:ns:caldav";
    public static readonly XNamespace CalServer = "http://calendarserver.org/ns/";
    public static readonly XNamespace Apple = "http://apple.com/ns/ical/";
}

public static class DavXml
{
    public const int MaxXmlBodyBytes = 1024 * 1024;

    /// <summary>Reads an XML request body safely (no DTD, no external entities). Returns null for an empty body.</summary>
    public static async Task<XDocument?> ReadBodyAsync(HttpRequest request)
    {
        using var buffer = new MemoryStream();
        await request.Body.CopyToAsync(buffer);
        if (buffer.Length == 0) return null;
        if (buffer.Length > MaxXmlBodyBytes) throw new BadRequestException("Request body too large");
        buffer.Position = 0;
        var settings = new XmlReaderSettings
        {
            DtdProcessing = DtdProcessing.Prohibit,
            XmlResolver = null,
            Async = true,
        };
        try
        {
            using var reader = XmlReader.Create(buffer, settings);
            return await XDocument.LoadAsync(reader, LoadOptions.None, CancellationToken.None);
        }
        catch (XmlException e)
        {
            throw new BadRequestException($"Invalid XML: {e.Message}");
        }
    }

    public static XElement Multistatus(IEnumerable<XElement> responses) =>
        new(Ns.Dav + "multistatus",
            new XAttribute(XNamespace.Xmlns + "d", Ns.Dav),
            new XAttribute(XNamespace.Xmlns + "c", Ns.CalDav),
            new XAttribute(XNamespace.Xmlns + "cs", Ns.CalServer),
            new XAttribute(XNamespace.Xmlns + "ical", Ns.Apple),
            responses);

    /// <summary>A &lt;response&gt; grouping properties by status code.</summary>
    public static XElement Response(string href, IEnumerable<(XElement Prop, int Status)> props)
    {
        var groups = props.GroupBy(p => p.Status).OrderBy(g => g.Key);
        return new XElement(Ns.Dav + "response",
            new XElement(Ns.Dav + "href", href),
            groups.Select(g => new XElement(Ns.Dav + "propstat",
                new XElement(Ns.Dav + "prop", g.Select(p => p.Prop)),
                new XElement(Ns.Dav + "status", StatusLine(g.Key)))));
    }

    public static XElement StatusResponse(string href, int status) =>
        new(Ns.Dav + "response",
            new XElement(Ns.Dav + "href", href),
            new XElement(Ns.Dav + "status", StatusLine(status)));

    public static string StatusLine(int status) => status switch
    {
        200 => "HTTP/1.1 200 OK",
        403 => "HTTP/1.1 403 Forbidden",
        404 => "HTTP/1.1 404 Not Found",
        424 => "HTTP/1.1 424 Failed Dependency",
        _ => $"HTTP/1.1 {status} Status",
    };

    public static async Task WriteAsync(HttpResponse response, int status, XElement root)
    {
        response.StatusCode = status;
        response.ContentType = "application/xml; charset=utf-8";
        var doc = new XDocument(new XDeclaration("1.0", "utf-8", null), root);
        var sb = new StringBuilder();
        await using (var writer = XmlWriter.Create(sb, new XmlWriterSettings
                     {
                         Async = true, OmitXmlDeclaration = false, Encoding = Encoding.UTF8,
                     }))
        {
            doc.Save(writer);
        }
        // StringBuilder output declares utf-16; fix the declaration.
        var text = sb.ToString().Replace("encoding=\"utf-16\"", "encoding=\"utf-8\"");
        await response.WriteAsync(text, Encoding.UTF8);
    }

    /// <summary>A DAV:error body with a precondition element.</summary>
    public static XElement Error(XName precondition, string? href = null) =>
        new(Ns.Dav + "error",
            new XAttribute(XNamespace.Xmlns + "d", Ns.Dav),
            new XAttribute(XNamespace.Xmlns + "c", Ns.CalDav),
            new XElement(precondition, href is null ? null : new XElement(Ns.Dav + "href", href)));
}

public class BadRequestException(string message) : Exception(message);
