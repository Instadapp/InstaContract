// const { assertRevert } = require('./helpers/general')

const InstaMaker = artifacts.require('InstaMaker')

contract('InstaMaker', accounts => {
  let instaMaker

  beforeEach(async () => {
    instaMaker = await InstaMaker.new(accounts[0])
  })

  it('should have an owner', async () => {
    const addressRegistry = await instaMaker.addressRegistry()
    assert.isTrue(addressRegistry == 0)
  })
})
