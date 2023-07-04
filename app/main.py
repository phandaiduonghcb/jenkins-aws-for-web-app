from fastapi import FastAPI

app = FastAPI()


@app.get('/')
async def root():
    return {'greeting': 'Hello from root function + Feature A'}


@app.get('/{name}')
async def hello(name: str):
    return {'greeting': f'Hello {name}!'}
