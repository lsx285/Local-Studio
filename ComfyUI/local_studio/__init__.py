import socket

from aiohttp import web
from pillow_heif import register_heif_opener
from zeroconf import IPVersion, ServiceInfo
from zeroconf.asyncio import AsyncZeroconf

from comfy.cli_args import args
from comfy.text_encoders.llama import generation_token_callback
from comfy_api.latest import ComfyExtension, io
from server import PromptServer
from .workflows import catalog, build_workflow

register_heif_opener()


class LocalStudioTextStream(io.ComfyNode):
    @classmethod
    def define_schema(cls):
        return io.Schema(
            node_id="LocalStudioTextStream", category="text", is_output_node=True,
            inputs=[io.Clip.Input("clip"), io.String.Input("prompt", multiline=True),
                    io.String.Input("client_id"), io.String.Input("request_id"),
                    io.Int.Input("max_tokens", default=1024, min=1, max=32768),
                    io.Int.Input("seed", default=0, min=0, max=0xffffffffffffffff),
                    io.Autogrow.Input("images", optional=True, template=io.Autogrow.TemplateNames(
                        io.Image.Input("image"), names=[f"image_{i}" for i in range(1, 9)], min=0))],
            outputs=[io.String.Output()])

    @classmethod
    def execute(cls, clip, prompt, client_id, request_id, max_tokens, seed, images=None):
        def emit(ids):
            text = clip.decode(ids)
            if not text.endswith("\ufffd"):
                PromptServer.instance.send_sync("local_studio_text", {"request_id": request_id, "text": text}, client_id)

        image_list = [image for image in (images or {}).values()]
        tokens = clip.tokenize(prompt, images=image_list, skip_template=True, min_length=1)
        context = generation_token_callback.set(emit)
        try:
            result = clip.generate(tokens, max_length=max_tokens, temperature=0.7, top_k=20,
                                   top_p=0.8, min_p=0.0, repetition_penalty=1.05, seed=seed, mtp=False)
        finally:
            generation_token_callback.reset(context)
        text = clip.decode(result)
        return io.NodeOutput(text, ui={"text": [text]})


@PromptServer.instance.routes.get("/local-studio/catalog")
async def get_catalog(request):
    return web.json_response({"version": 1, "models": catalog()})


@PromptServer.instance.routes.post("/local-studio/workflow")
async def workflow(request):
    try:
        return web.json_response(build_workflow(await request.json()))
    except (KeyError, ValueError) as error:
        return web.json_response({"error": str(error)}, status=400)


async def advertise(app):
    if args.listen == "127.0.0.1":
        return
    addresses = sorted({item[4][0] for item in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET)
                        if not item[4][0].startswith("127.")})
    if not addresses:
        return
    zeroconf = AsyncZeroconf(ip_version=IPVersion.V4Only)
    service = ServiceInfo("_localstudio._tcp.local.", f"Local Studio on {socket.gethostname()}._localstudio._tcp.local.",
                          parsed_addresses=addresses, port=args.port,
                          properties={"version": "1"}, server=f"{socket.gethostname()}.local.")
    await zeroconf.async_register_service(service)
    app["local_studio_discovery"] = (zeroconf, service)


async def stop_advertising(app):
    if "local_studio_discovery" in app:
        zeroconf, service = app["local_studio_discovery"]
        await zeroconf.async_unregister_service(service)
        await zeroconf.async_close()


PromptServer.instance.app.on_startup.append(advertise)
PromptServer.instance.app.on_cleanup.append(stop_advertising)


class LocalStudioExtension(ComfyExtension):
    async def get_node_list(self):
        return [LocalStudioTextStream]


async def comfy_entrypoint():
    return LocalStudioExtension()
