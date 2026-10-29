
using DotNetMvcTest.Data;
using DotNetMvcTest.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace DotNetMvcTest.Controllers;

[ApiController]
[Route("api/[controller]")]
public class ProductsController : ControllerBase
{
    private readonly AppDbContext _context;

    public ProductsController(AppDbContext context)
    {
        _context = context;
    }

    // GET: api/products
    [HttpGet]
    public async Task<ActionResult<IEnumerable<Product>>> GetAll()
    {
        var products = await _context.Products
            .AsNoTracking()
            .ToListAsync();

        return Ok(products);
    }

    // GET: api/products/1
    [HttpGet("{id:int}")]
    public async Task<ActionResult<Product>> GetById(int id)
    {
        var product = await _context.Products.FindAsync(id);

        if (product == null)
            return NotFound(new { message = "Product not found." });

        return Ok(product);
    }

    // POST: api/products
    [HttpPost]
    public async Task<ActionResult<Product>> Create(Product product)
    {
        _context.Products.Add(product);
        await _context.SaveChangesAsync();

        return CreatedAtAction(
            nameof(GetById),
            new { id = product.Id },
            product);
    }

    // PUT: api/products/1
    [HttpPut("{id:int}")]
    public async Task<IActionResult> Update(int id, Product updatedProduct)
    {
        if (id != updatedProduct.Id)
        {
            return BadRequest(new
            {
                message = "Route ID and product ID must match."
            });
        }

        var product = await _context.Products.FindAsync(id);

        if (product == null)
            return NotFound(new { message = "Product not found." });

        product.Name = updatedProduct.Name;
        product.Price = updatedProduct.Price;

        await _context.SaveChangesAsync();

        return Ok(product);
    }

    // DELETE: api/products/1
    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id)
    {
        var product = await _context.Products.FindAsync(id);

        if (product == null)
            return NotFound(new { message = "Product not found." });

        _context.Products.Remove(product);
        await _context.SaveChangesAsync();

        return NoContent();
    }
}
